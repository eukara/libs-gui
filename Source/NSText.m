/*
   NSText.m

   The RTFD text class

   Copyright (C) 1996 Free Software Foundation, Inc.

   Author:  Scott Christley <scottc@net-community.com>
   Date: 1996
   Author:  Felipe A. Rodriguez <far@ix.netcom.com>
   Date: July 1998
   Author:  Daniel B�hringer <boehring@biomed.ruhr-uni-bochum.de>
   Date: August 1998
   Author: Fred Kiefer <FredKiefer@gmx.de>
   Date: March 2000
   Reorganised and cleaned up code, added some action methods

   This file is part of the GNUstep GUI Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Library General Public
   License along with this library; see the file COPYING.LIB.
   If not, write to the Free Software Foundation,
   59 Temple Place - Suite 330, Boston, MA 02111 - 1307, USA.
*/

// toDo: - caret blinking
//	 - formatting routine: broader than 1.5x width cause display problems
//	 - optimization: 1.deletion of single char in paragraph [opti hook 1]
//	 - optimization: 2.newline in first line
//	 - optimization: 3.paragraph made one less line due to delition
//                         of single char [opti hook 1; diff from 1.]

#include <gnustep/gui/config.h>
#include <Foundation/NSNotification.h>
#include <Foundation/NSString.h>

#include <AppKit/NSFileWrapper.h>
#include <AppKit/NSControl.h>
#include <AppKit/NSText.h>
#include <AppKit/NSApplication.h>
#include <AppKit/NSWindow.h>
#include <AppKit/NSFontManager.h>
#include <AppKit/NSFont.h>
#include <AppKit/NSColor.h>
#include <AppKit/NSParagraphStyle.h>
#include <AppKit/NSPasteboard.h>
#include <AppKit/NSSpellChecker.h>
#include <AppKit/NSClipView.h>

#include <AppKit/NSDragging.h>
#include <AppKit/NSStringDrawing.h>
#include <AppKit/NSTextStorage.h>

#include <Foundation/NSNotification.h>
#include <Foundation/NSArchiver.h>
#include <Foundation/NSValue.h>
#include <Foundation/NSScanner.h>
#include <Foundation/NSData.h>

#define HUGE 1e99

enum {
  NSBackspaceKey      = 8,
  NSCarriageReturnKey = 13,
  NSDeleteKey         = 0x7f,
  NSBacktabKey        = 25
};

static NSCharacterSet *selectionWordGranularitySet;
static NSCharacterSet *selectionParagraphGranularitySet;

@interface _GNULineLayoutInfo: NSObject
{
@public
  NSRange	lineRange;
  NSRect	lineRect;
  float		drawingOffset;
  unsigned	type;
}

typedef enum
{
  // do not use 0 in order to secure calls to nil (calls to nil return 0)!
  LineLayoutInfoType_Text = 1,
  LineLayoutInfoType_Paragraph = 2
} _GNULineLayoutInfo_t;

+ (id) lineLayoutWithRange: (NSRange)aRange
		      rect: (NSRect)aRect
	     drawingOffset: (float)anOffset
		      type: (unsigned)aType;

- (NSRange) lineRange;
- (NSRect) lineRect;
- (float) drawingOffset;
- (unsigned) type;

- (void) setLineRange: (NSRange)aRange;
- (void) setLineRect: (NSRect)aRect;
- (void) setDrawingOffset: (float)anOffset;
- (void) setType: (unsigned)aType;

- (NSString*) description;
@end

@implementation _GNULineLayoutInfo

+ (id) lineLayoutWithRange: (NSRange)aRange
		      rect: (NSRect)aRect
	     drawingOffset: (float)anOffset
		      type: (unsigned)aType
{
  id ret = AUTORELEASE([_GNULineLayoutInfo new]);

  [ret setLineRange: aRange];
  [ret setLineRect: aRect];
  [ret setDrawingOffset: anOffset];
  [ret setType: aType];
  return ret;
}

- (unsigned) type
{
  return type;
}

- (NSRange) lineRange
{
  return lineRange;
}

- (NSRect) lineRect
{
  return lineRect;
}

- (float) drawingOffset
{
  return drawingOffset;
}

- (void) setLineRange: (NSRange)aRange
{
  lineRange = aRange;
}

- (void) setLineRect: (NSRect)aRect
{
  //FIXME, line up textEditor with how text in text cell will be placed.
  //  aRect.origin.y += 2;

  lineRect = aRect;
}

- (void) setDrawingOffset: (float)anOffset
{
  drawingOffset = anOffset;
}

- (void) setType: (unsigned)aType
{
  type = aType;
}

- (NSString*) description
{
  return [[NSDictionary dictionaryWithObjectsAndKeys:
			  NSStringFromRange(lineRange), @"LineRange",
			  NSStringFromRect(lineRect), @"LineRect",
			  nil]
	   description];
}

@end

static NSRange MakeRangeFromAbs (int a1,int a2) // not the same as NSMakeRange!
{
  if (a1 < 0)
    a1  = 0;
  if (a2 < 0)
    a2  = 0;
  if (a1 < a2)
    return NSMakeRange (a1, a2 - a1);
  else
    return NSMakeRange (a2, a1 - a2);
}

// end: _GNULineLayoutInfo------------------------------------------------------

@interface _GNUSeekableArrayEnumerator: NSObject
{
  unsigned	currentIndex;
  NSArray	*array;
}
- (id) initWithArray: (NSArray*)anArray;
- (id) nextObject;
- (id) previousObject;
- (id) currentObject;
@end

@implementation _GNUSeekableArrayEnumerator

- (id) initWithArray: (NSArray*)anArray
{
  self = [super init];
  array = RETAIN(anArray);
  return self;
}

- (id) nextObject
{
  if (currentIndex >= [array count])
    return nil;
  return [array objectAtIndex: currentIndex++];
}

- (id) previousObject
{
  if (currentIndex == 0)
    return nil;
  return [array objectAtIndex: --currentIndex];
}

- (id) currentObject
{
  return [array objectAtIndex: currentIndex];
}

- (void) dealloc
{
  RELEASE(array);
  [super dealloc];
}
@end

@interface NSArray(SeekableEnumerator)
- (_GNUSeekableArrayEnumerator*) seekableEnumerator;
@end
@implementation NSArray(SeekableEnumerator)
- (_GNUSeekableArrayEnumerator*) seekableEnumerator
{
  return AUTORELEASE([[_GNUSeekableArrayEnumerator alloc] initWithArray: self]);
}
@end



@interface NSText(GNUstepPrivate)
/*
 * these NSLayoutManager- like methods are here only informally (GNU extensions)
 */
- (unsigned) characterIndexForPoint: (NSPoint)point;
- (NSRect) rectForCharacterIndex: (unsigned)index;
- (void) _editedRange: (NSRange)aRange
	    withDelta: (int)delta;
- (void) _buildUpLayout;
- (void) drawRect: (NSRect)rect
    withSelection: (NSRange)range;

// GNU utility methods
- (void) _illegalMovement: (int) notNumber;
- (BOOL) performPasteOperation: (NSPasteboard*)pboard;

/*
 * various GNU extensions
 */

+ (void) setSelectionWordGranularitySet: (NSCharacterSet*)aSet;
+ (void) setSelectionParagraphGranularitySet: (NSCharacterSet*)aSet;

//
// private
//
- (void) deleteRange: (NSRange)aRange backspace: (BOOL)flag;
- (NSDictionary*) defaultTypingAttributes;

- (void) setSelectedRangeNoDrawing: (NSRange)range;
- (void) drawInsertionPointAtIndex: (unsigned)index
			     color: (NSColor*)color
			  turnedOn: (BOOL)flag;
- (void) drawSelectionAsRangeNoCaret: (NSRange)aRange;
- (void) drawSelectionAsRange: (NSRange)aRange;

- (NSRect) _textBounds;
@end


@interface GSSimpleLayoutManager: NSObject
{
  // contains private _GNULineLayoutInfo objects
  NSMutableArray	*lineLayoutInformation;
  NSText		*_textHolder;
  NSAttributedString	*_textStorage;
}

- (id) initForText: (NSText*) aTextHolder
withAttributedString: (NSAttributedString*) aString;
- (void) setAttributedString: (NSAttributedString*) aString;
- (NSSize) _sizeOfRange: (NSRange) range;
- (NSRect) _textBounds;


- (unsigned) characterIndexForPoint: (NSPoint)point;
- (NSRect) rectForCharacterIndex: (unsigned) index;
- (NSRange) characterRangeForBoundingRect: (NSRect)bounds;
- (NSRange) lineRangeForRect: (NSRect) aRect;

// return value is identical to the real line number
// (plus counted newline characters)
- (int) lineLayoutIndexForCharacterIndex: (unsigned) anIndex;
// returns the full character range for a line range
- (NSRange) characterRangeForLineLayoutRange: (NSRange) aRange;

- (void) setNeedsDisplayForLineRange: (NSRange) redrawLineRange;
- (void) _editedRange: (NSRange) aRange
	    withDelta: (int) delta;
- (int) rebuildLineLayoutInformation;
// override for special layout of text
- (int) rebuildLineLayoutInformationStartingAtLine: (int)aLine
					     delta: (int)insertionDelta
					actualLine: (int)insertionLine;
// low level, override but never invoke (use setNeedsDisplayForLineRange:)
- (void) drawLinesInLineRange: (NSRange)aRange;
- (NSRange) drawRectCharacters: (NSRect)rect;
@end

@implementation GSSimpleLayoutManager
- (id) initForText: (NSText*)aTextHolder
	withAttributedString: (NSAttributedString*)aString
{
  _textHolder = aTextHolder;
  [self setAttributedString: aString];
  return self;
}

- (void) setAttributedString: (NSAttributedString*)aString
{
  ASSIGN(_textStorage, aString);
  [self rebuildLineLayoutInformation];
}

- (NSSize) _sizeOfRange: (NSRange)aRange
{
  if (!aRange.length || _textStorage == nil ||
      NSMaxRange(aRange) > [_textStorage length])
    return NSZeroSize;

  return [[_textStorage attributedSubstringFromRange: aRange] size];
}

// Returns the currently used bounds for all the text
- (NSRect) _textBounds
{
  if ([lineLayoutInformation count])
    {
      NSEnumerator *lineEnum;
      _GNULineLayoutInfo *currentInfo;
      NSRect retRect = NSMakeRect (0, 0, 0, 0);

      for ((lineEnum = [lineLayoutInformation objectEnumerator]);
	   (currentInfo = [lineEnum nextObject]);)
	{
	  retRect = NSUnionRect (retRect, [currentInfo lineRect]);
	}
      return retRect;
    }
  else
    return NSZeroRect;
}

- (int) lineLayoutIndexForCharacterIndex: (unsigned)anIndex
{
  NSEnumerator		*lineEnum;
  _GNULineLayoutInfo	*currentInfo;

  if ([lineLayoutInformation count]
      && anIndex >= NSMaxRange ([[lineLayoutInformation lastObject] lineRange]))
    return [lineLayoutInformation count] - 1;

  // should use a faster search here
  for ((lineEnum = [lineLayoutInformation objectEnumerator]);
       (currentInfo = [lineEnum nextObject]);)
    {
      NSRange lineRange = [currentInfo lineRange];
      if (lineRange.location<= anIndex
	  && (anIndex <= NSMaxRange (lineRange)
	      - ([currentInfo type] == LineLayoutInfoType_Paragraph? 1: 0)))
	return [lineLayoutInformation indexOfObject: currentInfo];
    }

  return 0;
}

- (NSRange) characterRangeForLineLayoutRange: (NSRange)aRange;
{
  _GNULineLayoutInfo	*currentInfo;
  unsigned startLine = aRange.location;
  unsigned endLine = NSMaxRange(aRange);
  unsigned startIndex;
  unsigned endIndex;

  if (startLine >= [lineLayoutInformation count])
    currentInfo = [lineLayoutInformation lastObject];
  else
    currentInfo = [lineLayoutInformation objectAtIndex: startLine];
  startIndex = [currentInfo lineRange].location;

  if (endLine >= [lineLayoutInformation count])
    currentInfo = [lineLayoutInformation lastObject];
  else
    currentInfo = [lineLayoutInformation objectAtIndex: endLine];
  endIndex = NSMaxRange([currentInfo lineRange]);

  return MakeRangeFromAbs(startIndex, endIndex);
}

- (NSRange) characterRangeForBoundingRect: (NSRect)boundsRect
{
  NSRange lineRange = [self lineRangeForRect: boundsRect];

  if (lineRange.length)
    return [self characterRangeForLineLayoutRange: lineRange];
  else
    return NSMakeRange (0, 0);
}

- (unsigned) characterIndexForPoint: (NSPoint)point
{
  int i;
  NSEnumerator *lineEnum;
  _GNULineLayoutInfo *currentInfo;

  if (point.y >= NSMaxY([[lineLayoutInformation lastObject] lineRect]))
    return [_textStorage length];

  point.x = MAX(0,point.x);
  point.y = MAX(0,point.y);

  for (i = 0, (lineEnum = [lineLayoutInformation objectEnumerator]);
       (currentInfo = [lineEnum nextObject]);
       i++)
    // this loop holds some optimization potential (linear search)
    {
      NSRect rect = [currentInfo lineRect];

      if (NSMaxY(rect)>= point.y
	  && rect.origin.y<point.y
	  && rect.origin.x< point.x
	  && point.x >= NSMaxX(rect))
	return NSMaxRange ([currentInfo lineRange]);

      if (NSPointInRect (point, rect))
	{
	  int retPos = 0;
	  NSRange range = [currentInfo lineRange];

	  for (retPos = range.location; retPos<= NSMaxRange(range); retPos++)
	    // this loop holds some optimization potential (linear search)
	    {
	      if ([self _sizeOfRange:
			  NSMakeRange (range.location,
				       retPos - range.location)].width
		  >= point.x)
		return MAX (0, retPos - 1);
	    }
	  return range.location;
	}
    }

  return 0;
}

// rect to the end of line
- (NSRect) rectForCharacterIndex: (unsigned)index
{
  int i;
  float maxWidth = [_textHolder frame].size.width;
  NSEnumerator *lineEnum;
  _GNULineLayoutInfo *currentInfo;

  if (![lineLayoutInformation count])
    {
      return NSMakeRect (0, 0, maxWidth,
			 [self _sizeOfRange: NSMakeRange(0,1)].height);
    }

  if (index >= NSMaxRange([[lineLayoutInformation lastObject] lineRange]))
    {
      NSRect rect = [[lineLayoutInformation lastObject] lineRect];
      if (NSMaxX (rect) >= maxWidth)
	{
	  return NSMakeRect (0, NSMaxY(rect),
			     maxWidth, rect.size.height);
	}
      return NSMakeRect (NSMaxX (rect), rect.origin.y,
			 maxWidth - NSMaxX (rect),
			 rect.size.height);
    }

  for (i = 0, (lineEnum = [lineLayoutInformation objectEnumerator]);
       (currentInfo = [lineEnum nextObject]); i++)
    {
      NSRange	range = [currentInfo lineRange];
      if (NSLocationInRange (index, range))
	{
	  NSRect rect = [currentInfo lineRect];
	  NSSize stringSize
	    = [self _sizeOfRange: MakeRangeFromAbs (range.location, index)];
	  float x = rect.origin.x + stringSize.width;

	  return NSMakeRect (x, rect.origin.y, NSMaxX (rect) - x,
			     rect.size.height);
	}
    }

  return NSZeroRect;
}

- (unsigned) lineLayoutIndexForPoint: (NSPoint)point
{
  int i;
  NSEnumerator *lineEnum;
  _GNULineLayoutInfo *currentInfo;

  if  (point.y >= NSMaxY ([[lineLayoutInformation lastObject] lineRect]))
    return [lineLayoutInformation count] - 1;

  point.x = MAX (0, point.x);
  point.y = MAX (0, point.y);

  for (i = 0, (lineEnum = [lineLayoutInformation objectEnumerator]);
       (currentInfo = [lineEnum nextObject]); i++)
    {
      NSRect rect = [currentInfo lineRect];
      if (NSMaxY(rect) > point.y
	  && rect.origin.y <= point.y
	  && rect.origin.x < point.x
	  && point.x >= NSMaxX (rect))
	return [lineLayoutInformation indexOfObject: currentInfo];
      if (NSPointInRect (point, rect))
	{
	  // this loop holds some optimization potential (linear search)
	  int retPos = 0;
	  NSRange range = [currentInfo lineRange];

	  // this loop holds some optimization potential (linear search)
	  for (retPos = range.location; retPos<= NSMaxRange (range); retPos++)
	    {
	      if ([self _sizeOfRange:
			  NSMakeRange (range.location,
				       retPos - range.location)].width
		  >= point.x)
		return [lineLayoutInformation indexOfObject: currentInfo];
	    }
	  return [lineLayoutInformation indexOfObject: currentInfo];
	}
    }
  return 0;
}

- (void) setNeedsDisplayForLineRange: (NSRange)redrawLineRange
{
  NSRect myFrame = [_textHolder frame];
  float maxWidth = myFrame.size.width;

  if ([lineLayoutInformation count]
      && redrawLineRange.location < [lineLayoutInformation count]
      && redrawLineRange.length)
    {
      _GNULineLayoutInfo *firstInfo
	= [lineLayoutInformation objectAtIndex: redrawLineRange.location];
      NSRect displayRect, firstRect = [firstInfo lineRect];

      if ([firstInfo type]  == LineLayoutInfoType_Paragraph
	  && firstRect.origin.x >0 && redrawLineRange.location)
      {
	redrawLineRange.location--;
	redrawLineRange.length++;
      }

      displayRect
	= NSUnionRect ([[lineLayoutInformation
			  objectAtIndex: redrawLineRange.location]
			 lineRect],
		       [[lineLayoutInformation
			  objectAtIndex:
			    MAX (0, (int)NSMaxRange (redrawLineRange) - 1)]
			 lineRect]);

      displayRect.size.width = maxWidth - displayRect.origin.x;
      [_textHolder setNeedsDisplayInRect: displayRect];
    }


  // clean up the remaining area below the text
    {
      float lowestY = 0;

      if ([lineLayoutInformation count])
	lowestY = NSMaxY ([[lineLayoutInformation lastObject] lineRect]);

      if (![lineLayoutInformation count]
	  || (lowestY < NSMaxY(myFrame)))
	{
	  [_textHolder setNeedsDisplayInRect: NSMakeRect(0, lowestY,
						  myFrame.size.width,
						  NSMaxY (myFrame) - lowestY)];
	}
    }
}

- (void) _editedRange: (NSRange)aRange
	    withDelta: (int)delta
{
  int start = [self lineLayoutIndexForCharacterIndex: aRange.location];
  int count;
  int origLineIndex = MAX(0, start - 1);

  count = [self rebuildLineLayoutInformationStartingAtLine: origLineIndex
		delta: delta
		actualLine: start];
  [self setNeedsDisplayForLineRange: NSMakeRange(origLineIndex, MAX(1, count))];
}

// internal method <!> range is currently not passed as absolute
- (void) addNewlines: (NSRange)aRange
     intoLayoutArray: (NSMutableArray*)anArray
	     atPoint: (NSPoint*)aPointP
	       width: (float)width
      characterIndex: (unsigned)startingLineCharIndex
     ghostEnumerator: (_GNUSeekableArrayEnumerator*)prevArrayEnum
	    didShift: (BOOL*)didShift
verticalDisplacement: (float*)verticalDisplacement
{
  NSSize advanceSize = [self _sizeOfRange:
			       NSMakeRange (startingLineCharIndex, 1)];
  int count = aRange.length,charIndex;
  _GNULineLayoutInfo *thisInfo,*ghostInfo = nil;

  (*didShift) = NO;

  for (charIndex = aRange.location; --count >= 0; charIndex++)
    {
      NSRect currentLineRect;

      currentLineRect = NSMakeRect (aPointP ->x, aPointP ->y,
				    width - aPointP ->x, advanceSize.height);
      [anArray addObject:
		 thisInfo = [_GNULineLayoutInfo
			      lineLayoutWithRange:
				NSMakeRange (startingLineCharIndex, 1)
			      rect: currentLineRect
			      drawingOffset: 0
			      type: LineLayoutInfoType_Paragraph]];

      startingLineCharIndex++;
      aPointP ->x = 0;
      aPointP ->y += advanceSize.height;

      if (prevArrayEnum && !(ghostInfo = [prevArrayEnum nextObject]))
	prevArrayEnum = nil;

      if (ghostInfo && ([thisInfo type] != [ghostInfo type]))
	{
	  _GNULineLayoutInfo *prevInfo = [prevArrayEnum previousObject];
	  prevArrayEnum = nil;
	  (*didShift) = YES;
	  (*verticalDisplacement) += aPointP ->y - [prevInfo lineRect].origin.y;
	}
    }
}

// private helper function
static unsigned
_relocLayoutArray (NSMutableArray *lineLayoutInformation,
		   NSArray *ghostArray,
		   int aLine,
		   int relocOffset,
		   int rebuildLineDrift,
		   float yReloc)
{
  // lines actually updated (optimized drawing)
  unsigned ret = [lineLayoutInformation count] - aLine;
  NSArray *relocArray
    = [ghostArray subarrayWithRange:
		    MakeRangeFromAbs (MAX (0, ret + rebuildLineDrift),
				      [ghostArray count])];
  NSEnumerator *relocEnum;
  _GNULineLayoutInfo *currReloc;

  if (![relocArray count])
    return ret;

  for ((relocEnum = [relocArray objectEnumerator]);
       (currReloc = [relocEnum nextObject]);)
    {
      NSRange range = [currReloc lineRange];
      [currReloc setLineRange: NSMakeRange (range.location + relocOffset,
					    range.length)];
      if (yReloc)
	{
	  NSRect rect = [currReloc lineRect];
	  [currReloc setLineRect: NSMakeRect (rect.origin.x,
					      rect.origin.y + yReloc,
					      rect.size.width,
					      rect.size.height)];
	}
    }
  [lineLayoutInformation addObjectsFromArray: relocArray];
  return ret;
}

/*
 * A little utility function to determine the range of characters in a scanner
 * that are present in a specified character set.
 */
static inline NSRange
scanRange(NSScanner *scanner, NSCharacterSet* aSet)
{
  unsigned	start = [scanner scanLocation];
  unsigned	end = start;

  if ([scanner scanCharactersFromSet: aSet intoString: 0] == YES)
    {
      end = [scanner scanLocation];
    }
  return NSMakeRange(start, end - start);
}

// begin: central line formatting method---------------------------------------
// returns count of lines actually updated
// <!> detachNewThreadSelector: selector toTarget: target withObject: argument;

- (int) rebuildLineLayoutInformationStartingAtLine: (int)aLine
					     delta: (int)insertionDelta
					actualLine: (int)insertionLineIndex
{
  NSPoint		drawingPoint = NSZeroPoint;
  NSScanner		*pScanner;
  float			width = [_textHolder frame].size.width;
  unsigned		startingIndex = 0;
  unsigned              currentLineIndex;
  NSArray		*ghostArray;	// for optimization detection
  _GNUSeekableArrayEnumerator *prevArrayEnum;
  NSCharacterSet *invSelectionWordGranularitySet
    = [selectionWordGranularitySet invertedSet];
  NSCharacterSet *invSelectionParagraphGranularitySet
    = [selectionParagraphGranularitySet invertedSet];
  NSString *parsedString;
  BOOL isHorizontallyResizable = [_textHolder isHorizontallyResizable];
  int lineDriftOffset = 0, rebuildLineDrift = 0;
  BOOL frameshiftCorrection = NO, nlDidShift = NO, enforceOpti = NO;
  float	yDisplacement = 0;

  // sanity check that it is possible to do the layout
  if (width == 0.0)
    {
      NSLog(@"NSText formatting with empty frame");
      return 0;
    }

  if (!lineLayoutInformation)
    {
      lineLayoutInformation = [[NSMutableArray alloc] init];
      aLine = 0;
      ghostArray = nil;
      prevArrayEnum = nil;
    }
  else
    {
      // remember old array for optimization purposes
      ghostArray = [lineLayoutInformation
		     subarrayWithRange:
		       NSMakeRange (aLine, [lineLayoutInformation count] - aLine)];
      // every time an object is added to lineLayoutInformation
      // a nextObject has to be performed on prevArrayEnum!
      prevArrayEnum = [ghostArray seekableEnumerator];

      if (aLine)
	{
	  _GNULineLayoutInfo	*lastValidLineInfo;

	  lastValidLineInfo = [lineLayoutInformation objectAtIndex: aLine - 1];
	  drawingPoint = [lastValidLineInfo lineRect].origin;
	  drawingPoint.y += [lastValidLineInfo lineRect].size.height;
	  startingIndex = NSMaxRange([lastValidLineInfo lineRange]);
	  if ([lastValidLineInfo type] == LineLayoutInfoType_Paragraph)
	    {
	      drawingPoint.x = 0;
	    }
	  // keep paragraph - terminating space on same line as paragraph
	  if ((((int)[lineLayoutInformation count]) - 1) >= aLine)
	    {
	      _GNULineLayoutInfo *anchorLine
		= [lineLayoutInformation objectAtIndex: aLine];
	      NSRect anchorRect = [anchorLine lineRect];

	      if (anchorRect.origin.x > drawingPoint.x
		  && [lastValidLineInfo lineRect].origin.y == anchorRect.origin.y)
		{
		  drawingPoint = anchorRect.origin;
		}
	    }
	}

      [lineLayoutInformation
	removeObjectsInRange:
	  NSMakeRange (aLine, [lineLayoutInformation count] - aLine)];
    }

  currentLineIndex = aLine;

  // each paragraph
  parsedString = [[_textStorage string] substringFromIndex: startingIndex];
  pScanner = [NSScanner scannerWithString: parsedString];
  [pScanner setCharactersToBeSkipped: nil];
  while ([pScanner isAtEnd] == NO)
    {
      NSScanner	*lScanner;
      NSString	*paragraph;
      NSRange	paragraphRange, leadingNlRange, trailingNlRange;
      unsigned	currentLoc = [pScanner scanLocation];
      unsigned	startingParagraphIndex = currentLoc + startingIndex;
      unsigned	startingLineCharIndex = startingParagraphIndex;
      BOOL	isBuckled = NO, inBuckling = NO;

      leadingNlRange
	= scanRange(pScanner, selectionParagraphGranularitySet);
      paragraphRange
	= scanRange(pScanner, invSelectionParagraphGranularitySet);
      trailingNlRange
	= scanRange(pScanner, selectionParagraphGranularitySet);

      if (leadingNlRange.length > 0)
	{
	  [self addNewlines: leadingNlRange
	    intoLayoutArray: lineLayoutInformation
		    atPoint: &drawingPoint
		      width: width
	     characterIndex: startingLineCharIndex
	    ghostEnumerator: prevArrayEnum
		   didShift: &nlDidShift
       verticalDisplacement: &yDisplacement];

	  if (nlDidShift)
	    {
	      if (insertionDelta  == 1)
		{
		  frameshiftCorrection = YES;
		  rebuildLineDrift--;
		}
	      else if (insertionDelta  == - 1)
		{
		  frameshiftCorrection = YES;
		  rebuildLineDrift++;
		}
	      else nlDidShift = NO;
	    }

	  startingLineCharIndex += leadingNlRange.length;
	  currentLineIndex += leadingNlRange.length;
	}

      // each line
      paragraph = [parsedString substringWithRange: paragraphRange];
      lScanner = [NSScanner scannerWithString: paragraph];
      [lScanner setCharactersToBeSkipped: nil];
      while ([lScanner isAtEnd] == NO)
	{
	  NSRect	currentLineRect = NSMakeRect (0, drawingPoint.y, 0, 0);
	  // starts with zero, do not confuse with startingLineCharIndex
	  unsigned	localLineStartIndex = [lScanner scanLocation];
	  NSSize	advanceSize = NSZeroSize;

	  // scan the individual words to the end of the line
	  for (; ![lScanner isAtEnd]; drawingPoint.x += advanceSize.width)
	    {
	      NSRange	currentStringRange, trailingSpacesRange;
	      NSRange	leadingSpacesRange;
	      unsigned	scannerPosition = [lScanner scanLocation];

	      // snack next word

	      // leading spaces: only first time
	      leadingSpacesRange
		= scanRange(lScanner, selectionWordGranularitySet);
	      currentStringRange
		= scanRange(lScanner, invSelectionWordGranularitySet);
	      trailingSpacesRange
		= scanRange(lScanner, selectionWordGranularitySet);

	      if (leadingSpacesRange.length)
		currentStringRange = NSUnionRange(leadingSpacesRange,
						   currentStringRange);
	      if (trailingSpacesRange.length)
		currentStringRange = NSUnionRange(trailingSpacesRange,
						   currentStringRange);

	      // evaluate size of current word and line so far
	      advanceSize = [self _sizeOfRange:
				    NSMakeRange (currentStringRange.location +
						 paragraphRange.location +
						 startingIndex,
						 currentStringRange.length)];

	      currentLineRect = NSUnionRect (currentLineRect,
					     NSMakeRect (drawingPoint.x,
							 drawingPoint.y,
							 advanceSize.width,
							 advanceSize.height));

	      // handle case where single word is broader than width
	      // (buckle word) <!> unfinished and untested
	      // for richText (absolute position see above)
	      if (!isHorizontallyResizable && advanceSize.width >= width)
		{
		  if (isBuckled)
		    {
		      NSSize currentSize = NSMakeSize (HUGE, 0);
		      unsigned lastVisibleCharIndex;

		      for (lastVisibleCharIndex
			     = startingLineCharIndex + currentStringRange.length;
			   currentSize.width>= width
			     && lastVisibleCharIndex> startingLineCharIndex;
			   lastVisibleCharIndex--)
			{
			  currentSize = [self _sizeOfRange:
						MakeRangeFromAbs (startingLineCharIndex,
								  lastVisibleCharIndex)];
			}
		      isBuckled = NO;
		      inBuckling = YES;
		      scannerPosition
			= localLineStartIndex
			+ (lastVisibleCharIndex - startingLineCharIndex);
		      currentLineRect.size.width = advanceSize.width = width;
		    }
		  else
		    {
		      // undo layout of extralarge word
		      // (will be done the next line [see above])
		      isBuckled = YES;
		      currentLineRect.size.width -= advanceSize.width;
		    }
		}

	      // end of line -> word wrap

	      // >= : wichtig f�r abknicken (isBuckled)
	      if (!isHorizontallyResizable
		  && (currentLineRect.size.width >= width || isBuckled))				{
		_GNULineLayoutInfo *ghostInfo = nil, *thisInfo;

		// undo layout of last word
		[lScanner setScanLocation: scannerPosition];

		currentLineRect.origin.x = 0;
		currentLineRect.origin.y = drawingPoint.y;
		drawingPoint.y += currentLineRect.size.height;
		drawingPoint.x = 0;

		[lineLayoutInformation
		  addObject: (thisInfo
			      = [_GNULineLayoutInfo
				  lineLayoutWithRange:
				    NSMakeRange (startingLineCharIndex,
						 scannerPosition - localLineStartIndex)
				  rect: currentLineRect
				  drawingOffset: 0
				  type: LineLayoutInfoType_Text])];

		currentLineIndex++;
		startingLineCharIndex = NSMaxRange([thisInfo lineRange]);

		if (prevArrayEnum
		    && !(ghostInfo = [prevArrayEnum nextObject]))
		  prevArrayEnum = nil;

		// optimization stuff
		// (do relayout only as much lines as necessary
		// and patch the rest)---------
		if (ghostInfo)
		  {
		    if ([ghostInfo type] != [thisInfo type])
		      {
			// frameshift correction
			frameshiftCorrection = YES;
			if (insertionDelta  == - 1)
			  {
			    // deletition of newline
			    _GNULineLayoutInfo *nextObject;
			    if (!(nextObject = [prevArrayEnum nextObject]))
			      prevArrayEnum = nil;
			    else
			      {
				if (nlDidShift && frameshiftCorrection)
				  {
				    //	frameshiftCorrection = NO;
#if 0
				    NSLog(@"opti hook 1 (preferred)");
#endif
				  }
				else
				  {
				    lineDriftOffset
				      += ([thisInfo lineRange].length
					  - [ghostInfo lineRange].length
					  - [nextObject lineRange].length);
				    yDisplacement
				      += [thisInfo lineRect].origin.y
				      - [nextObject lineRect].origin.y;
				    rebuildLineDrift++;
				  }
			      }
			  }
		      }
		    else
		      lineDriftOffset += ([thisInfo lineRange].length
					  - [ghostInfo lineRange].length);

		    // is it possible to simply patch layout changes
		    // into layout array instead of doing a time
		    // consuming re - layout of the whole doc?
		    if ((currentLineIndex - 1 > insertionLineIndex
			 && !inBuckling && !isBuckled)
			&& (!(lineDriftOffset - insertionDelta)
			    || (nlDidShift && !lineDriftOffset)
			    || enforceOpti))
		      {
			unsigned erg = _relocLayoutArray (lineLayoutInformation,
							  ghostArray,
							  aLine,
							  insertionDelta,
							  rebuildLineDrift,
							  yDisplacement);

			// y displacement: redisplay all remaining lines
			if (frameshiftCorrection)
			  erg = [lineLayoutInformation count] - aLine;
			else if (currentLineIndex - 1  == insertionLineIndex
				 && ABS(insertionDelta) == 1)
			  {
			    // return 2: redisplay only this and previous line
			    erg = 2;
			  }
#if 0
			NSLog(@"opti for: %d",erg);
#endif
			return erg;
		      }
		  }
		// end: optimization stuff--------------------------
		// -----------------------------------------------
		break;

		// newline - induced premature lineending: flush
	      }
	      else if ([lScanner isAtEnd])
		{
		  _GNULineLayoutInfo *thisInfo;
		  scannerPosition = [lScanner scanLocation];
		  [lineLayoutInformation
		    addObject: (thisInfo
				= [_GNULineLayoutInfo
				    lineLayoutWithRange:
				      NSMakeRange (startingLineCharIndex,
						   scannerPosition - localLineStartIndex)
				    rect: currentLineRect
				    drawingOffset: 0
				    type: LineLayoutInfoType_Text])];
		  currentLineIndex++;
		  startingLineCharIndex = NSMaxRange ([thisInfo lineRange]);

		  // check for optimization (lines after paragraph
		  // are unchanged and do not need redisplay/relayout)------
		  if (prevArrayEnum)
		    {
		      _GNULineLayoutInfo *ghostInfo = nil;

		      ghostInfo = [prevArrayEnum nextObject];

		      if (ghostInfo)
			{
			  if ([ghostInfo type] != [thisInfo type])
			    {
			      // frameshift correction for inserted newline
			      frameshiftCorrection = YES;

			      if (insertionDelta  == 1)
				{
				  [prevArrayEnum previousObject];
				  lineDriftOffset
				    += ([thisInfo lineRange].length
					- [ghostInfo lineRange].length) + insertionDelta;
				  rebuildLineDrift--;
				  yDisplacement
				    += [thisInfo lineRect].origin.y
				    - [ghostInfo lineRect].origin.y;
				}
			      else if (insertionDelta  == - 1)
				{
				  if (nlDidShift && frameshiftCorrection)
				    {
				      //	frameshiftCorrection = NO;
#if 0
				      NSLog(@"opti hook 2");
#endif
				    }
				}
			    }
			  else
			    lineDriftOffset
			      += ([thisInfo lineRange].length
				  - [ghostInfo lineRange].length);
			}
		      else
			{
			  // new array obviously longer than the previous one
			  prevArrayEnum = nil;
			}
		      // end: optimization stuff------------------------------
		      // -------------------------------------------
		    }
		}
	    }
	}
      // add the trailing newlines of current paragraph if any
      if (trailingNlRange.length)
	{
	  [self addNewlines: trailingNlRange
		intoLayoutArray: lineLayoutInformation
		atPoint: &drawingPoint
		width: width
		characterIndex: startingLineCharIndex
		ghostEnumerator: prevArrayEnum
		didShift: &nlDidShift
		verticalDisplacement: &yDisplacement];
	  if (nlDidShift)
	    {
	      if (insertionDelta == 1)
		{
		  frameshiftCorrection = YES;
		  rebuildLineDrift--;
		}
	      else if (insertionDelta == - 1)
		{
		  frameshiftCorrection = YES;
		  rebuildLineDrift++;
		}
	      else nlDidShift = NO;
	    }
	  currentLineIndex += trailingNlRange.length;
	}
    }

  // lines actually updated (optimized drawing)
  return [lineLayoutInformation count] - aLine;
}
// end: central line formatting method------------------------------------

- (int) rebuildLineLayoutInformation
{
  // force complete re - layout
  RELEASE(lineLayoutInformation);
  lineLayoutInformation = nil;
  return [self rebuildLineLayoutInformationStartingAtLine: 0
	       delta: 0
	       actualLine: 0];
}


// relies on lineLayoutInformation
- (void) drawLinesInLineRange: (NSRange)aRange;
{
  NSArray *linesToDraw = [lineLayoutInformation subarrayWithRange: aRange];
  NSEnumerator *lineEnum;
  _GNULineLayoutInfo *currentInfo;

  for ((lineEnum = [linesToDraw objectEnumerator]);
       (currentInfo = [lineEnum nextObject]);)
    {
      if ([currentInfo type] == LineLayoutInfoType_Paragraph)
	continue;	// e.g. for nl

      [_textStorage drawRange: [currentInfo lineRange]
		    atPoint: [currentInfo lineRect].origin];
	  // <!> make this use drawRange: inRect: in the future
	  // (for proper adoption of layout information [e.g. centering])
    }
}

// Draws the lines in the given rectangle and hands back the drawn 
// character range.
- (NSRange) drawRectCharacters: (NSRect)rect
{
  NSRange aRange = [self lineRangeForRect: rect];

  [self drawLinesInLineRange: aRange];
  return [self characterRangeForLineLayoutRange: aRange];
}

- (NSRange) lineRangeForRect: (NSRect)rect
{
  NSPoint upperLeftPoint = rect.origin;
  NSPoint lowerRightPoint = NSMakePoint (NSMaxX (rect), NSMaxY (rect));
  unsigned startLine, endLine;

  startLine = [self lineLayoutIndexForPoint: upperLeftPoint];
  endLine = [self lineLayoutIndexForPoint: lowerRightPoint];
  if (++endLine > [lineLayoutInformation count])
    endLine = [lineLayoutInformation count];

  return NSMakeRange(startLine, endLine - startLine);
}

@end




// begin: NSText------------------------------------------------------------

@implementation NSText

//
// Class methods
//
+ (void)initialize
{
  if (self  == [NSText class])
    {
      NSArray  *r;
      NSArray  *s;

      [self setVersion: 1];                     // Initial version

      [self setSelectionWordGranularitySet:
	      [NSCharacterSet whitespaceCharacterSet]];
      [self setSelectionParagraphGranularitySet:
	      [NSCharacterSet characterSetWithCharactersInString:
				[self newlineString]]];
      r  = [NSArray arrayWithObjects: NSStringPboardType, nil];
      s  = [NSArray arrayWithObjects: NSStringPboardType, nil];

      [[NSApplication sharedApplication] registerServicesMenuSendTypes: s
                                                          returnTypes: r];
    }
}

//
// Instance methods
//
//
// Initialization
//

- (id) init
{
  return [self initWithFrame: NSMakeRect (0, 0, 100, 100)];
}

- (id) initWithFrame: (NSRect)frameRect
{
  [super initWithFrame: frameRect];

  [self setMinSize: frameRect.size];
  [self setMaxSize: NSMakeSize(HUGE,HUGE)];

  _alignment = NSLeftTextAlignment;
  _tf.is_editable = YES;
  _tf.is_selectable = YES;
  _tf.is_rich_text = NO;
  _tf.uses_font_panel = NO;
  _tf.is_horizontally_resizable = NO;
  _tf.is_vertically_resizable = YES;
  _tf.is_ruler_visible = NO;
  _tf.is_field_editor = NO;
  _tf.draws_background = YES;
  [self setBackgroundColor: [NSColor textBackgroundColor]];
  [self setTextColor: [NSColor textColor]];
  _default_font = RETAIN([NSFont userFontOfSize: 12]);
  // sets up the contents object
  [self setString: @""];
  //[self setSelectedRange: NSMakeRange (0, 0)];
  return self;
}

- (void)dealloc
{
  [self unregisterDraggedTypes];
  RELEASE(_background_color);
  RELEASE(_default_font);
  RELEASE(_text_color);
  RELEASE(_textStorage);

  [super dealloc];
}

/*
 * Getting and Setting Contents
 */
- (void) replaceCharactersInRange: (NSRange)aRange
			  withRTF: (NSData*)rtfData
{
  [self replaceCharactersInRange: aRange withRTFD: rtfData];
}

- (void) replaceCharactersInRange: (NSRange)aRange
			 withRTFD: (NSData*)rtfdData
{
  [self replaceRange: aRange
	withAttributedString: AUTORELEASE([[NSAttributedString alloc]
				 initWithRTFD: rtfdData
				 documentAttributes: NULL])];
}

- (void) replaceCharactersInRange: (NSRange)aRange
		       withString: (NSString*)aString
{
  [_textStorage replaceCharactersInRange: aRange withString: aString];

  [self _editedRange: aRange
	withDelta: [aString length] - aRange.length];
}

- (void) setString: (NSString*)aString
{
  RELEASE(_textStorage);
  _textStorage = [[NSMutableAttributedString alloc]
		   initWithString: aString
		   attributes: [self defaultTypingAttributes]];

  [self _buildUpLayout];
  [self sizeToFit];
  [self setSelectedRangeNoDrawing: NSMakeRange (0, 0)];
  [self setNeedsDisplay: YES];
}

- (NSString*) string
{
    return [_textStorage string];
}

// old methods
- (void) replaceRange: (NSRange)aRange withRTFD: (NSData*)rtfdData
{
  [self replaceCharactersInRange: aRange withRTFD: rtfdData];
}

- (void) replaceRange: (NSRange)aRange withRTF: (NSData*)rtfData
{
  [self replaceCharactersInRange: aRange withRTF: rtfData];
}

- (void) replaceRange: (NSRange)aRange withString: (NSString*)aString
{
  [self replaceCharactersInRange: aRange withString: aString];
}

- (void) setText: (NSString*)aString range: (NSRange)aRange
{
  [self replaceCharactersInRange: aRange withString: aString];
}

- (void) setText: (NSString*)string
{
  [self setString: string];
}

- (NSString*) text
{
  return [self string];
}

//
// Graphic attributes
//
- (NSColor*) backgroundColor
{
  return _background_color;
}

- (BOOL) drawsBackground
{
  return _tf.draws_background;
}

- (void) setBackgroundColor: (NSColor*)color
{
  ASSIGN(_background_color, color);
}

- (void)setDrawsBackground: (BOOL)flag
{
  _tf.draws_background = flag;
}

//
// Managing Global Characteristics
//
- (BOOL) importsGraphics
{
  return _tf.imports_graphics;
}

- (BOOL) isEditable
{
  return _tf.is_editable;
}

- (BOOL) isFieldEditor
{
  return _tf.is_field_editor;
}

- (BOOL) isRichText
{
  return _tf.is_rich_text;
}

- (BOOL) isSelectable
{
  return _tf.is_selectable;
}

- (void)setEditable: (BOOL)flag
{
  _tf.is_editable = flag;
  // If we are editable then we  are selectable
  if (flag)
    {
      _tf.is_selectable = YES;
      // FIXME: We should show the insertion point
    }
}

- (void) setFieldEditor: (BOOL)flag
{
  _tf.is_field_editor = flag;
}

- (void)setImportsGraphics: (BOOL)flag
{
  _tf.imports_graphics = flag;
  [self updateDragTypeRegistration];
}

- (void) setRichText: (BOOL)flag
{
  _tf.is_rich_text  = flag;
  if (!flag)
    {
      [self setString: [self string]];
    }

  [self updateDragTypeRegistration];
}

- (void)setSelectable: (BOOL)flag
{
  _tf.is_selectable = flag;
  // If we are not selectable then we must not be editable
  if (!flag)
    _tf.is_editable = NO;
}

//
// Using the font panel
//
- (BOOL) usesFontPanel
{
  return _tf.uses_font_panel;
}

- (void)setUsesFontPanel: (BOOL)flag
{
  _tf.uses_font_panel = flag;
}

//
// Managing the Ruler
//
- (BOOL) isRulerVisible
{
  return NO;
}

- (void) toggleRuler: (id)sender
{
}

//
// Managing the Selection
//
- (NSRange)selectedRange
{
  return _selected_range;
}


- (void) setSelectedRange: (NSRange)range
{
  BOOL didLock = NO;

  if (!_window)
    return;

  if ([[self class] focusView] != self)
    {
      [self lockFocus];
      didLock = YES;
    }

  if (_selected_range.length == 0)	// remove old cursor
    {
      [self drawInsertionPointAtIndex: _selected_range.location
	    color: nil turnedOn: NO];
    }
  else
    {
      // This does an unhighlight of the old selected region
      [self drawSelectionAsRange: _selected_range];
    }

  [self setSelectedRangeNoDrawing: range];

  // display
  if (range.length)
    {
      // <!>disable caret timed entry
    }
  else	// no selection
    {
      if ([self isRichText])
	{
	  [self setTypingAttributes: [NSMutableDictionary
				       dictionaryWithDictionary:
					 [_textStorage
					   attributesAtIndex: range.location
					   effectiveRange: NULL]]];
	}
      // <!>enable caret timed entry
    }
  [self drawSelectionAsRange: range];
  [self scrollRangeToVisible: range];

  if (didLock)
    {
      [self unlockFocus];
      [_window flushWindow];
    }
}

/*
 * Copy and paste
 */
- (void) copy: (id)sender
{
  NSMutableArray *types = [NSMutableArray arrayWithObject:
					    NSStringPboardType];
  NSPasteboard *pboard = [NSPasteboard generalPasteboard];

  if ([self isRichText])
    [types addObject: NSRTFPboardType];

  if (_tf.imports_graphics)
    [types addObject: NSRTFDPboardType];

  [pboard declareTypes: types owner: self];

  [pboard setString: [[self string] substringWithRange: _selected_range]
	  forType: NSStringPboardType];

  if ([self isRichText])
    [pboard setData: [self RTFFromRange: _selected_range]
	    forType: NSRTFPboardType];

  if (_tf.imports_graphics)
    [pboard setData: [self RTFDFromRange: _selected_range]
	    forType: NSRTFDPboardType];
}

// Copy the current font to the font pasteboard
- (void) copyFont: (id)sender
{
  NSMutableArray *types = [NSMutableArray arrayWithObject:
					    NSFontPboardType];
  NSPasteboard *pboard = [NSPasteboard pasteboardWithName: NSFontPboard];
  // FIXME: We should get the font from the selection
  NSFont *font = [self font];
  NSData *data = nil;

  if (font != nil)
    data = [NSArchiver archivedDataWithRootObject: font];

  if (data != nil)
    {
      [pboard declareTypes: types owner: self];
      [pboard setData: data forType: NSFontPboardType];
    }
}

// Copy the current ruler settings to the ruler pasteboard
- (void) copyRuler: (id)sender
{
  NSMutableArray *types = [NSMutableArray arrayWithObject:
					    NSRulerPboardType];
  NSPasteboard *pboard = [NSPasteboard pasteboardWithName: NSRulerPboard];
  NSParagraphStyle *style;
  NSData * data = nil;

  if (![self isRichText])
    return;

  style = [_textStorage attribute: NSParagraphStyleAttributeName
			atIndex: _selected_range.location
			effectiveRange: &_selected_range];

  if (style != nil)
    data = [NSArchiver archivedDataWithRootObject: style];

  if (data != nil)
    {
      [pboard declareTypes: types owner: self];
      [pboard setData: data forType: NSRulerPboardType];
    }
}

- (void) delete: (id)sender
{
  [self deleteRange: _selected_range backspace: NO];
}

- (void) cut: (id)sender
{
  if (_selected_range.length)
    {
      [self copy: sender];
      [self delete: sender];
    }
}

- (void) paste: (id)sender
{
  [self performPasteOperation: [NSPasteboard generalPasteboard]];
}

- (void) pasteFont: (id)sender
{
  [self performPasteOperation:
	  [NSPasteboard pasteboardWithName: NSFontPboard]];
}

- (void) pasteRuler: (id)sender
{
  [self performPasteOperation:
	  [NSPasteboard pasteboardWithName: NSRulerPboard]];
}

- (void) selectAll: (id)sender
{
  [self setSelectedRange: NSMakeRange(0,[self textLength])];
}

/*
 * Managing Font and Color
 */
- (NSFont*) font
{
  // FIXME: Should take the font of the first text, if there is some
  return _default_font;
}

/*
 * This action method changes the font of the selection for a rich text object,
 * or of all text for a plain text object. If the receiver doesn't use the Font
 * Panel, however, this method does nothing.
 */
- (void) changeFont: (id)sender
{
  if (_tf.uses_font_panel)
    {
      if ([self isRichText])
	{
	  NSRange searchRange = _selected_range;
	  NSRange foundRange;
	  int maxSelRange;

	  for (maxSelRange = NSMaxRange(_selected_range);
	       searchRange.location < maxSelRange;
	       searchRange = NSMakeRange (NSMaxRange (foundRange),
					  maxSelRange - NSMaxRange(foundRange)))
	    {
	      NSFont *font = [_textStorage attribute: NSFontAttributeName
					   atIndex: searchRange.location
					   longestEffectiveRange: &foundRange
					   inRange: searchRange];
	      if (font)
		{
		  [self setFont: [sender convertFont: font]
			ofRange: foundRange];
		}
	    }
	}
      else
	{
	  [self setFont: [sender convertFont: _default_font]];
	}
      [self setNeedsDisplay: YES];
    }
}

- (void) setFont: (NSFont*)font
{
  NSRange fullRange = NSMakeRange(0, [[self string] length]);

  ASSIGN(_default_font, font);
  [_textStorage addAttribute: NSFontAttributeName
		value: font
		range: fullRange];
  [self _editedRange: fullRange
	withDelta: 0];
}

- (void) setFont: (NSFont*)font
	 ofRange: (NSRange)aRange
{
  if ([self isRichText])
    {
      if (font != nil)
	{
	  [_textStorage addAttribute: NSFontAttributeName
		      value: font
		      range: aRange];
	  [self _editedRange: aRange
		withDelta: 0];
	}
    }
}

/*
 * Managing Alingment
 */
- (NSTextAlignment) alignment
{
  return _alignment;
}

- (void) setAlignment: (NSTextAlignment) mode
{
  _alignment = mode;
  [self setNeedsDisplay: YES];
}

- (void) alignCenter: (id) sender
{
  if ([self isRichText])
    {
      [_textStorage setAlignment: NSCenterTextAlignment
		    range: _selected_range];
      [self setNeedsDisplay: YES];
    }
  else
    [self setAlignment: NSCenterTextAlignment];
}

- (void) alignLeft: (id) sender
{
  if ([self isRichText])
    {
      [_textStorage setAlignment: NSLeftTextAlignment
		    range: _selected_range];
      [self setNeedsDisplay: YES];
    }
  else
    [self setAlignment: NSLeftTextAlignment];
}

- (void) alignRight: (id) sender
{
  if ([self isRichText])
    {
      [_textStorage setAlignment: NSRightTextAlignment
		    range: _selected_range];
      [self setNeedsDisplay: YES];
    }
  else
    [self setAlignment: NSRightTextAlignment];
}

/*
 * Text colour
 */
- (NSColor*) textColor
{
  return _text_color;
}

- (void) setTextColor: (NSColor*) color
		range: (NSRange) aRange
{
  if ([self isRichText])
    {
      if (color != nil)
	[_textStorage addAttribute: NSForegroundColorAttributeName
		      value: color
		      range: aRange];
    }
}

- (void) setColor: (NSColor*) color
	  ofRange: (NSRange) aRange
{
  [self setTextColor: color range: aRange];
}

- (void) setTextColor: (NSColor*) color
{
  ASSIGN (_text_color, color);
  if (![self isRichText])
    [self setNeedsDisplay: YES];
}

//
// Text attributes
//
- (void) subscript: (id)sender
{
  if ([self isRichText])
    {
      if (_selected_range.length)
	{
	  [_textStorage subscriptRange: _selected_range];
	  [self _editedRange: _selected_range
		withDelta: 0];
	}
    }
}

- (void) superscript: (id)sender
{
  if ([self isRichText])
    {
      if (_selected_range.length)
	{
	  [_textStorage superscriptRange: _selected_range];
	  [self _editedRange: _selected_range
		withDelta: 0];
	}
    }
}

- (void) unscript: (id)sender
{
  if ([self isRichText])
    {
      if (_selected_range.length)
	{
	  [_textStorage unscriptRange: _selected_range];
	  [self _editedRange: _selected_range
		withDelta: 0];
	}
    }
}

- (void) underline: (id)sender
{
  if ([self isRichText])
    {
      BOOL doUnderline = YES;
      if ([[_textStorage attribute: NSUnderlineStyleAttributeName
		       atIndex: _selected_range.location
		       effectiveRange: NULL] intValue])
	doUnderline = NO;

      if (_selected_range.length)
	{
	  [_textStorage addAttribute: NSUnderlineStyleAttributeName
		      value: [NSNumber numberWithInt: doUnderline]
		      range: _selected_range];
	  [self _editedRange: _selected_range
		withDelta: 0];
	}
      else  // no redraw necess.
	[[self typingAttributes]
	  setObject: [NSNumber numberWithInt: doUnderline]
	  forKey: NSUnderlineStyleAttributeName];
    }
}

//
// Reading and Writing RTFD Files
//
- (BOOL) readRTFDFromFile: (NSString*)path
{
  NSData *data = [NSData dataWithContentsOfFile: path];
  id peek;

  if (data && (peek = AUTORELEASE([[NSAttributedString alloc] initWithRTF: data
						   documentAttributes: NULL]
			)))
    {
      if (!_tf.is_rich_text)
	{
	  // not [self setRichText: YES] for efficiancy reasons
	  _tf.is_rich_text = YES;
	  [self updateDragTypeRegistration];
	}
      [self replaceRange: NSMakeRange (0, [self textLength])
	    withAttributedString: peek];
      return YES;
    }
  return NO;
}

- (BOOL) writeRTFDToFile: (NSString*)path atomically: (BOOL)flag
{
  NSFileWrapper *wrapper = [_textStorage RTFDFileWrapperFromRange:
					   NSMakeRange(0, [_textStorage length])
					 documentAttributes: nil];
  return [wrapper writeToFile: path atomically: flag updateFilenames: YES];
}

- (NSData*) RTFDFromRange: (NSRange) aRange
{
  return [_textStorage RTFDFromRange: aRange
		       documentAttributes: nil];
}

- (NSData*) RTFFromRange: (NSRange) aRange
{
  return [self RTFDFromRange: aRange];
}

//
// Sizing the Frame Rectangle
//
- (void) setFrame: (NSRect) frameRect
{
  // FIXME: This should clear the now empty space,
  // when shrinking
  [super setFrame: frameRect];
}

- (BOOL) isHorizontallyResizable
{
  return _tf.is_horizontally_resizable;
}

- (BOOL) isVerticallyResizable
{
  return _tf.is_vertically_resizable;
}

- (NSSize) maxSize
{
  return _maxSize;
}

- (NSSize) minSize
{
  return _minSize;
}

- (void)setHorizontallyResizable: (BOOL)flag
{
  _tf.is_horizontally_resizable = flag;
}

- (void)setMaxSize: (NSSize)newMaxSize
{
  _maxSize = newMaxSize;
}

- (void)setMinSize: (NSSize)newMinSize
{
  _minSize = newMinSize;
}

- (void) setVerticallyResizable: (BOOL)flag
{
  _tf.is_vertically_resizable = flag;
}

- (void) sizeToFit
{
  // if we are a field editor we don't have to handle the size.
  if ([self isFieldEditor])
    return;
  else
    {
      NSSize oldSize = _frame.size;
      float newWidth = oldSize.width;
      float newHeight = oldSize.height;
      NSRect textRect = [self _textBounds];
      NSSize newSize;

      if (_tf.is_horizontally_resizable)
	{
	  newWidth = textRect.size.width;
	}
      else if (_tf.is_vertically_resizable)
	{
	  newHeight = textRect.size.height;
	}

      newSize = NSMakeSize(MIN(_maxSize.width, MAX(newWidth, _minSize.width)),
			   MIN(_maxSize.height, MAX(newHeight, _minSize.height)));
      if (!NSEqualSizes(oldSize, newSize))
	{
	  [self setFrameSize: newSize];
	}
    }
}

//
// Spelling
//

- (void) checkSpelling: (id)sender
{
  NSRange errorRange
    = [[NSSpellChecker sharedSpellChecker]
	checkSpellingOfString: [self string]
	startingAt: NSMaxRange (_selected_range)];

  if (errorRange.length)
    [self setSelectedRange: errorRange];
  else
    NSBeep();
}

- (void) showGuessPanel: (id)sender
{
  [[[NSSpellChecker sharedSpellChecker] spellingPanel] orderFront: self];
}

//
// Scrolling
//

- (void) scrollRangeToVisible: (NSRange) aRange
{
  [self scrollRectToVisible:
	  NSUnionRect ([self rectForCharacterIndex:
			       _selected_range.location],
		       [self rectForCharacterIndex:
			       NSMaxRange (_selected_range)])];
}

/*
 * Managing the Delegate
 */
- (id) delegate
{
  return _delegate;
}

- (void) setDelegate: (id) anObject
{
  NSNotificationCenter *nc  = [NSNotificationCenter defaultCenter];

  if (_delegate)
    [nc removeObserver: _delegate name: nil object: self];
  ASSIGN(_delegate, anObject);

#define SET_DELEGATE_NOTIFICATION(notif_name) \
  if ([_delegate respondsToSelector: @selector(text##notif_name:)]) \
    [nc addObserver: _delegate \
          selector: @selector(text##notif_name:) \
              name: NSText##notif_name##Notification \
            object: self]

  SET_DELEGATE_NOTIFICATION(DidBeginEditing);
  SET_DELEGATE_NOTIFICATION(DidChange);
  SET_DELEGATE_NOTIFICATION(DidEndEditing);
}

//
// Handling Events
//
- (void) mouseDown: (NSEvent*)theEvent
{
  NSSelectionGranularity granularity = NSSelectByCharacter;
  NSRange chosenRange, prevChosenRange, proposedRange;
  NSPoint point, startPoint;
  NSEvent *currentEvent;
  unsigned startIndex;
  BOOL didDragging = NO;

  // If not selectable then don't recognize the mouse down
  if (!_tf.is_selectable)
    return;

  if (![_window makeFirstResponder: self])
    return;

  switch ([theEvent clickCount])
    {
    case 1: granularity = NSSelectByCharacter;
      break;
    case 2: granularity = NSSelectByWord;
      break;
    case 3: granularity = NSSelectByParagraph;
      break;
    }

  startPoint = [self convertPoint: [theEvent locationInWindow] fromView: nil];
  startIndex = [self characterIndexForPoint: startPoint];

  proposedRange = NSMakeRange (startIndex, 0);
  chosenRange = prevChosenRange = [self selectionRangeForProposedRange:
					  proposedRange
					granularity: granularity];

  [self lockFocus];

  // clean up before doing the dragging
  if (_selected_range.length == 0)	// remove old cursor
    {
      [self drawInsertionPointAtIndex: _selected_range.location
	    color: nil turnedOn: NO];
    }
  else
    [self drawSelectionAsRangeNoCaret: _selected_range];

  //<!> make this non - blocking (or make use of timed entries)
  for (currentEvent = [_window
			nextEventMatchingMask:
			  (NSLeftMouseDraggedMask|NSLeftMouseUpMask)];
       [currentEvent type] != NSLeftMouseUp;
       (currentEvent = [_window
			 nextEventMatchingMask:
			   (NSLeftMouseDraggedMask|NSLeftMouseUpMask)]),
	 prevChosenRange = chosenRange)	// run modal loop
    {
      BOOL didScroll = [self autoscroll: currentEvent];
      point = [self convertPoint: [currentEvent locationInWindow]
		    fromView: nil];
      proposedRange = MakeRangeFromAbs ([self characterIndexForPoint: point],
					startIndex);
      chosenRange = [self selectionRangeForProposedRange: proposedRange
			  granularity: granularity];

      if (NSEqualRanges (prevChosenRange, chosenRange))
	{
	  if (!didDragging)
	    {
	      [self drawSelectionAsRangeNoCaret: chosenRange];
	      [_window flushWindow];
	    }
	  else
	    continue;
	}
      // this changes the selection without needing instance drawing
      // (carefully thought out ; - )
      if (!didScroll)
	{
	  [self drawSelectionAsRangeNoCaret:
		  MakeRangeFromAbs (MIN (chosenRange.location,
					 prevChosenRange.location),
				    MAX (chosenRange.location,
					 prevChosenRange.location))];
	  [self drawSelectionAsRangeNoCaret:
		  MakeRangeFromAbs (MIN (NSMaxRange (chosenRange),
					 NSMaxRange (prevChosenRange)),
				    MAX (NSMaxRange (chosenRange),
					 NSMaxRange (prevChosenRange)))];
	  [_window flushWindow];
	}
      else
	{
	  [self drawRect: [self visibleRect] withSelection: chosenRange];
	  [_window flushWindow];
	}

      didDragging = YES;
    }

  NSDebugLog(@"chosenRange. location  = % d, length  = %d\n",
	     (int)chosenRange.location, (int)chosenRange.length);

  [self setSelectedRangeNoDrawing: chosenRange];
  if (!didDragging)
    [self drawSelectionAsRange: chosenRange];
  else if (chosenRange.length  == 0)
    [self drawInsertionPointAtIndex: chosenRange.location
	  color: [NSColor blackColor] turnedOn: YES];

  // remember for column stable cursor up/down
  _currentCursor = [self rectForCharacterIndex: chosenRange.location].origin;

  [self unlockFocus];
  [_window flushWindow];
}

- (void) keyDown: (NSEvent*)theEvent
{
  // If not editable then don't recognize the key down
  if (!_tf.is_editable)
    {
      [super keyDown: theEvent];
    }
  else
    {
      [self interpretKeyEvents: [NSArray arrayWithObject: theEvent]];
    }
}

- (void) insertNewline: (id) sender
{
  if (_tf.is_field_editor)
    {
      [self _illegalMovement: NSReturnTextMovement];
      return;
    }

  [self insertText: [[self class] newlineString]];
}

- (void) insertTab: (id) sender
{
  if (_tf.is_field_editor)
    {
      [self _illegalMovement: NSTabTextMovement];
      return;
    }

  [self insertText: @"\t"];
}

- (void) insertBacktab: (id) sender
{
  if (_tf.is_field_editor)
    {
      [self _illegalMovement: NSBacktabTextMovement];
      return;
    }

  //[self insertText: @"\t"];
}

- (void) deleteForward: (id) sender
{
  if (_selected_range.location != [self textLength])
    {
      /* Not at the end of text -- delete following character */
      [self deleteRange:
	      [self selectionRangeForProposedRange:
		      NSMakeRange (_selected_range.location, 1)
		    granularity: NSSelectByCharacter]
	    backspace: NO];
    }
  else
    {
      /* end of text: behave the same way as NSBackspaceKey */
      [self deleteBackward: sender];
    }
}

- (void) deleteBackward: (id) sender
{
  [self deleteRange: _selected_range backspace: YES];
}

//<!> choose granularity according to keyboard modifier flags
- (void) moveUp: (id) sender
{
  unsigned cursorIndex;
  NSPoint cursorPoint;
  NSRange oldRange = _selected_range;

  if (_tf.is_field_editor)
    {
      [self _illegalMovement: NSUpTextMovement];
      return;
    }

  /* Do nothing if we are at beginning of text */
  if (_selected_range.location == 0)
    return;

  if (_selected_range.length)
    {
      _currentCursor = [self rectForCharacterIndex:
			       _selected_range.location].origin;
    }
  cursorIndex = _selected_range.location;
  cursorPoint = [self rectForCharacterIndex: cursorIndex].origin;
  cursorIndex = [self characterIndexForPoint:
			NSMakePoint (_currentCursor.x + 0.001,
				     MAX (0, cursorPoint.y - 0.001))];
  [self setSelectedRange: [self selectionRangeForProposedRange:
				  NSMakeRange (cursorIndex, 0)
				granularity: NSSelectByCharacter]];
  // FIXME: We redisplay the line the cursor was on.
  [self setNeedsDisplayInRect: [self rectForCharacterIndex:
				       oldRange.location]];
}

- (void) moveDown: (id) sender
{
  unsigned cursorIndex;
  NSRect cursorRect;
  NSRange oldRange = _selected_range;

  if (_tf.is_field_editor)
    {
      [self _illegalMovement: NSDownTextMovement];
      return;
    }

  /* Do nothing if we are at end of text */
  if (_selected_range.location == [self textLength])
    return;

  if (_selected_range.length)
    {
      _currentCursor = [self rectForCharacterIndex:
			       NSMaxRange (_selected_range)].origin;
    }
  cursorIndex = _selected_range.location;
  cursorRect = [self rectForCharacterIndex: cursorIndex];
  cursorIndex = [self characterIndexForPoint:
			NSMakePoint (_currentCursor.x + 0.001,
				     NSMaxY (cursorRect) + 0.001)];
  [self setSelectedRange: [self selectionRangeForProposedRange:
				  NSMakeRange (cursorIndex, 0)
				granularity: NSSelectByCharacter]];
  // FIXME: We redisplay the line the cursor was on
  [self setNeedsDisplayInRect: [self rectForCharacterIndex:
				       oldRange.location]];
}

- (void) moveLeft: (id) sender
{
  /* Do nothing if we are at beginning of text */
  if (_selected_range.location == 0)
    return;

  [self setSelectedRange:
	  [self selectionRangeForProposedRange:
		  NSMakeRange (_selected_range.location - 1, 0)
		granularity: NSSelectByCharacter]];
  _currentCursor.x = [self rectForCharacterIndex:
			   _selected_range.location].origin.x;
  // FIXME: We redisplay the line the cursor is on.
  [self setNeedsDisplayInRect: [self rectForCharacterIndex:
				       _selected_range.location + 1]];
}

- (void) moveRight: (id) sender
{
  /* Do nothing if we are at end of text */
  if (_selected_range.location == [self textLength])
    return;

  [self setSelectedRange:
	  [self selectionRangeForProposedRange:
		  NSMakeRange (MIN (NSMaxRange (_selected_range) + 1,
				    [self textLength]), 0)
		granularity: NSSelectByCharacter]];
  _currentCursor.x = [self rectForCharacterIndex:
			   _selected_range.location].origin.x;
  // FIXME: We redisplay the line the cursor is on.
  [self setNeedsDisplayInRect: [self rectForCharacterIndex:
				       _selected_range.location - 1]];
}

- (BOOL) acceptsFirstResponder
{
  if ([self isSelectable])
    return YES;
  else
    return NO;
}

- (BOOL) resignFirstResponder
{
  if (([self isEditable])
      && ([_delegate respondsToSelector: @selector(textShouldEndEditing:)])
      && ([_delegate textShouldEndEditing: self] == NO))
    return NO;

  // Add any clean-up stuff here

  if ([self shouldDrawInsertionPoint])
    {
      [self drawInsertionPointAtIndex: _selected_range.location
	    color: nil turnedOn: NO];

      //<!> stop timed entry
    }

  [[NSNotificationCenter defaultCenter]
    postNotificationName: NSTextDidEndEditingNotification
    object: self];
  return YES;
}

- (BOOL) becomeFirstResponder
{
  if ([self isSelectable] == NO)
    return NO;

  if (([_delegate respondsToSelector: @selector(textShouldBeginEditing:)])
      && ([_delegate textShouldBeginEditing: self] == NO))
    return NO;

  // Add any initialization stuff here.

  //if ([self shouldDrawInsertionPoint])
  //  {
  //   [self lockFocus];
  //   [self drawInsertionPointAtIndex: _selected_range.location
  //      color: [NSColor blackColor] turnedOn: YES];
  //   [self unlockFocus];
  //   //<!> restart timed entry
  //  }
  [[NSNotificationCenter defaultCenter]
    postNotificationName: NSTextDidBeginEditingNotification
    object: self];
  return YES;
}

- (void) drawRect: (NSRect)rect
{
  [self drawRect: rect withSelection: _selected_range];
}

// text lays out from top to bottom
- (BOOL) isFlipped
{
  return YES;
}

- (BOOL) isOpaque
{
  if (_tf.draws_background == NO
      || _background_color == nil
      || [_background_color alphaComponent] < 1.0)
    return NO;
  else
    return YES;
}


/*
 *     Handle enabling/disabling of services menu items.
 */
- (id) validRequestorForSendType: (NSString*) sendType
		      returnType: (NSString*) returnType
{
  if ((!sendType || [sendType isEqual: NSStringPboardType])
      && (!returnType || [returnType isEqual: NSStringPboardType]))
    {
      if ((_selected_range.length || !sendType)
	  && ([self isEditable] || !returnType))
	{
	  return self;
	}
    }
  return [super validRequestorForSendType: sendType
		returnType: returnType];

}

//
// NSCoding protocol
//
- (void)encodeWithCoder: aCoder
{
  BOOL flag;
  [super encodeWithCoder: aCoder];

  [aCoder encodeConditionalObject: _delegate];

  [aCoder encodeObject: _textStorage];

  [aCoder encodeValueOfObjCType: "I" at: &_alignment];
  flag = _tf.is_editable;
  [aCoder encodeValueOfObjCType: @encode(BOOL) at: &flag];
  flag = _tf.is_rich_text;
  [aCoder encodeValueOfObjCType: @encode(BOOL) at: &flag];
  flag = _tf.is_selectable;
  [aCoder encodeValueOfObjCType: @encode(BOOL) at: &flag];
  flag = _tf.imports_graphics;
  [aCoder encodeValueOfObjCType: @encode(BOOL) at: &flag];
  flag = _tf.uses_font_panel;
  [aCoder encodeValueOfObjCType: @encode(BOOL) at: &flag];
  flag = _tf.is_horizontally_resizable;
  [aCoder encodeValueOfObjCType: @encode(BOOL) at: &flag];
  flag = _tf.is_vertically_resizable;
  [aCoder encodeValueOfObjCType: @encode(BOOL) at: &flag];
  flag = _tf.is_ruler_visible;
  [aCoder encodeValueOfObjCType: @encode(BOOL) at: &flag];
  flag = _tf.is_field_editor;
  [aCoder encodeValueOfObjCType: @encode(BOOL) at: &flag];
  [aCoder encodeObject: _background_color];
  [aCoder encodeObject: _text_color];
  [aCoder encodeObject: _default_font];
  [aCoder encodeValueOfObjCType: @encode(NSRange) at: &_selected_range];
}

- initWithCoder: aDecoder
{
  BOOL flag;
  [super initWithCoder: aDecoder];

  _delegate  = [aDecoder decodeObject];

  _textStorage = [aDecoder decodeObject];

  [aDecoder decodeValueOfObjCType: "I" at: &_alignment];
  [aDecoder decodeValueOfObjCType: @encode(BOOL) at: &flag];
  _tf.is_editable = flag;
  [aDecoder decodeValueOfObjCType: @encode(BOOL) at: &flag];
  _tf.is_rich_text = flag;
  [aDecoder decodeValueOfObjCType: @encode(BOOL) at: &flag];
  _tf.is_selectable = flag;
  [aDecoder decodeValueOfObjCType: @encode(BOOL) at: &flag];
  _tf.imports_graphics = flag;
  [aDecoder decodeValueOfObjCType: @encode(BOOL) at: &flag];
  _tf.uses_font_panel = flag;
  [aDecoder decodeValueOfObjCType: @encode(BOOL) at: &flag];
  _tf.is_horizontally_resizable = flag;
  [aDecoder decodeValueOfObjCType: @encode(BOOL) at: &flag];
  _tf.is_vertically_resizable = flag;
  [aDecoder decodeValueOfObjCType: @encode(BOOL) at: &flag];
  _tf.is_ruler_visible = flag;
  [aDecoder decodeValueOfObjCType: @encode(BOOL) at: &flag];
  _tf.is_field_editor = flag;
  _background_color  = [aDecoder decodeObject];
  _text_color  = RETAIN([aDecoder decodeObject]);
  _default_font  = RETAIN([aDecoder decodeObject]);
  [aDecoder decodeValueOfObjCType: @encode(NSRange) at: &_selected_range];

  // build upt the layout information that dont get stored
  [self _buildUpLayout];
  return self;
}

//
// NSChangeSpelling protocol
//

- (void) changeSpelling: (id)sender
{
  [self insertText: [[(NSControl*)sender selectedCell] stringValue]];
}

//
// NSIgnoreMisspelledWords protocol
//
- (void) ignoreSpelling: (id)sender
{
  [[NSSpellChecker sharedSpellChecker]
    ignoreWord: [[(NSControl*)sender selectedCell] stringValue]
    inSpellDocumentWithTag: [self spellCheckerDocumentTag]];
}
@end

@implementation NSText(GNUstepExtension)

+ (NSString*) newlineString
{
  return @"\n";
}

- (void) replaceRange: (NSRange) aRange
 withAttributedString: (NSAttributedString*) attrString
{
  if ([self isRichText])
    [_textStorage replaceCharactersInRange: aRange
		  withAttributedString: attrString];
  else
    [_textStorage replaceCharactersInRange: aRange
		  withString: [attrString string]];

  [self _editedRange: aRange
	withDelta: [attrString length] - aRange.length];
}

- (unsigned) textLength
{
  return [_textStorage length];
}

- (void) sizeToFit: (id)sender
{
  [self sizeToFit];
}

- (int) spellCheckerDocumentTag
{
  if (!_spellCheckerDocumentTag)
    _spellCheckerDocumentTag = [NSSpellChecker uniqueSpellDocumentTag];

  return _spellCheckerDocumentTag;
}

// central text inserting method (takes care
// of optimized redraw/ cursor positioning)
- (void) insertText: (NSString*) insertString
{
  if ([self isRichText])
    {
      [self replaceRange: _selected_range
	    withAttributedString: AUTORELEASE([[NSAttributedString alloc]
				     initWithString: insertString
				     attributes: [self typingAttributes]])];
    }
  else
    {
      [self replaceCharactersInRange: _selected_range
	    withString: insertString];
    }

  // ScrollView interaction
  [self sizeToFit];

  // move cursor <!> [self selectionRangeForProposedRange: ]
  [self setSelectedRange:
	  NSMakeRange (_selected_range.location + [insertString length], 0)];

  // remember x for row - stable cursor movements
  _currentCursor = [self rectForCharacterIndex:
			   _selected_range.location].origin;

  // broadcast notification
  [[NSNotificationCenter defaultCenter]
    postNotificationName: NSTextDidChangeNotification
    object: self];
}

- (void) setTypingAttributes: (NSDictionary*) dict
{
  if (![dict isKindOfClass: [NSMutableDictionary class]])
    {
      RELEASE(_typingAttributes);
      _typingAttributes = [[NSMutableDictionary alloc] initWithDictionary: dict];
    }
  else
    ASSIGN(_typingAttributes, (NSMutableDictionary*)dict);
}

- (NSMutableDictionary*) typingAttributes
{
  if (_typingAttributes != nil)
    return _typingAttributes;
  else
    return [NSMutableDictionary dictionaryWithDictionary:
				  [self defaultTypingAttributes]];
}

- (void) updateFontPanel
{
  // update fontPanel only if told so
  if (_tf.uses_font_panel)
    {
      BOOL isMultiple = NO;
      NSFont *currentFont = nil;

      if ([self isRichText])
	{
	  NSRange longestRange;

	  currentFont = [_textStorage attribute: NSFontAttributeName
				    atIndex: _selected_range.location
				    longestEffectiveRange: &longestRange
				    inRange: _selected_range];

	  if (NSEqualRanges (longestRange, _selected_range))
	    isMultiple = NO;
	  else
	    isMultiple = YES;
	}
      else
	currentFont = _default_font;

      [[NSFontManager sharedFontManager] setSelectedFont: currentFont
					 isMultiple: isMultiple];
    }
}

- (BOOL) shouldDrawInsertionPoint
{
  return (_selected_range.length == 0) && [self isEditable];
}

- (void) drawInsertionPointInRect: (NSRect)rect
			    color: (NSColor*)color
			 turnedOn: (BOOL)flag
{
  BOOL	didLock  = NO;

  if (!_window)
    return;

  if ([[self class] focusView] != self)
    {
      [self lockFocus];
      didLock  = YES;
    }

  if (flag)
    {
      [color set];
      NSRectFill(rect);
    }
  else
    {
      [[self backgroundColor] set];
      NSRectFill(rect);
    }

  if (didLock)
    {
      [self unlockFocus];
      [_window flushWindow];
    }
}

- (NSRange) selectionRangeForProposedRange: (NSRange)proposedCharRange
			       granularity: (NSSelectionGranularity)granularity
{
  NSCharacterSet *set = nil;
  NSString *string = [self string];
  unsigned lastIndex = [string length] - 1;
  unsigned lpos = MIN(lastIndex, proposedCharRange.location);
  // <!>better: rpos = MAX(0, (int)NSMaxRange(proposedCharRange) - 1);
  unsigned rpos = NSMaxRange(proposedCharRange);
  BOOL rmemberstate, lmemberstate;

  if (![string length])
    {
      return NSMakeRange(0,0);
    }

  switch (granularity)
    {
    case NSSelectByCharacter:
      return NSIntersectionRange (proposedCharRange,
				  NSMakeRange (0, lastIndex + 2));
    case NSSelectByWord:
      set = selectionWordGranularitySet;
      break;
    case NSSelectByParagraph:
      set = selectionParagraphGranularitySet;
      break;
    }
  // now work on set...
  lmemberstate = [set characterIsMember: [string characterAtIndex: lpos]];
  rmemberstate = [set characterIsMember: [string characterAtIndex:
						   MIN (rpos, lastIndex)]];
  while (rpos <= lastIndex
	 && ([set characterIsMember: [string characterAtIndex: rpos]]
	     == rmemberstate))
    rpos++;

  while (lpos
	 && ([set characterIsMember: [string characterAtIndex: lpos]]
	     == lmemberstate))
    lpos--;

  if ([set characterIsMember: [string characterAtIndex: lpos]] != lmemberstate
      && lpos < proposedCharRange.location)
    lpos++;

  return MakeRangeFromAbs(lpos,rpos);
}

- (NSArray*) acceptableDragTypes
{
  NSMutableArray *ret = [NSMutableArray arrayWithObjects: NSStringPboardType,
					NSColorPboardType, nil];

  if ([self isRichText])
    [ret addObject: NSRTFPboardType];
  if (_tf.imports_graphics)
    [ret addObject: NSRTFDPboardType];
  return ret;
}

- (void) updateDragTypeRegistration
{
  [self registerForDraggedTypes: [self acceptableDragTypes]];
}

@end

@implementation NSText(GNUstepPrivate)


+ (void) setSelectionWordGranularitySet: (NSCharacterSet*) aSet
{
  ASSIGN(selectionWordGranularitySet, aSet);
}

+ (void) setSelectionParagraphGranularitySet: (NSCharacterSet*) aSet
{
  ASSIGN(selectionParagraphGranularitySet, aSet);
}

- (NSDictionary*) defaultTypingAttributes
{
  return [NSDictionary dictionaryWithObjectsAndKeys:
			 _default_font, NSFontAttributeName,
		         _text_color, NSForegroundColorAttributeName,
		         nil];
}

- (void) _illegalMovement: (int) textMovement
{
  // This is similar to [self resignFirstResponder],
  // with the difference that in the notification we need
  // to put the NSTextMovement, which resignFirstResponder
  // does not.  Also, if we are ending editing, we are going
  // to be removed, so it's useless to update any drawing.
  NSNumber *number;
  NSDictionary *uiDictionary;
  
  if (([self isEditable])
      && ([_delegate respondsToSelector:
		       @selector(textShouldEndEditing:)])
      && ([_delegate textShouldEndEditing: self] == NO))
    return;
  
  // Add any clean-up stuff here
  
  number = [NSNumber numberWithInt: textMovement];
  uiDictionary = [NSDictionary dictionaryWithObject: number
			       forKey: @"NSTextMovement"];
  [[NSNotificationCenter defaultCenter]
    postNotificationName: NSTextDidEndEditingNotification
    object: self
    userInfo: uiDictionary];
  return;
}

// begin: dragging of colors and files---------------
- (unsigned int) draggingEntered: (id <NSDraggingInfo>)sender
{
  return NSDragOperationGeneric;
}

- (unsigned int) draggingUpdated: (id <NSDraggingInfo>)sender
{
  return NSDragOperationGeneric;
}

- (void) draggingExited: (id <NSDraggingInfo>)sender
{
}

- (BOOL) prepareForDragOperation: (id <NSDraggingInfo>)sender
{
  return YES;
}

- (BOOL) performDragOperation: (id <NSDraggingInfo>)sender
{
  return [self performPasteOperation: [sender draggingPasteboard]];
}

- (void) concludeDragOperation: (id <NSDraggingInfo>)sender
{
}
// end: drag accepting---------------------------------


- (BOOL) writeSelectionToPasteboard: (NSPasteboard*)pb
                             types: (NSArray*)sendTypes
{
  NSArray      *types;
  NSString     *string;

  if ([sendTypes containsObject: NSStringPboardType] == NO)
    {
      return NO;
    }
  types = [NSArray arrayWithObjects: NSStringPboardType, nil];
  [pb declareTypes: types owner: nil];
  string = [self string];
  string = [string substringWithRange: _selected_range];
  return [pb setString: string forType: NSStringPboardType];
}

// <!>
// handle ruler pasteboard as well!
- (BOOL) performPasteOperation: (NSPasteboard*)pboard
{
  // color accepting
  if ([pboard availableTypeFromArray: [NSArray arrayWithObject:
						 NSColorPboardType]])
    {
      NSColor	*color = [NSColor colorFromPasteboard: pboard];

      if ([self isRichText])
	{
	  [self setTextColor: color range: _selected_range];
	}
      else
	[self setTextColor: color];
      return YES;
    }

  // font pasting
  if ([pboard availableTypeFromArray: [NSArray arrayWithObject:
						 NSFontPboardType]])
    {
      NSData *data = [pboard dataForType: NSFontPboardType];

      if (data != nil)
	{
	  NSFont *font = [NSUnarchiver unarchiveObjectWithData: data];

	  if (font != nil)
	    {
	      if ([self isRichText])
		{
		  if (_selected_range.length)
		    [self setFont: font ofRange: _selected_range];
		  else
		    [[self typingAttributes]
		      setObject: font
		      forKey: NSFontAttributeName];
		}
	      else
		[self setFont: font];
	      return YES;
	    }
	}
      //return NO;
    }

  if (_tf.imports_graphics)
    {
      NSArray *types = [NSArray arrayWithObjects: NSFileContentsPboardType,
				NSRTFDPboardType, NSRTFPboardType,
				NSStringPboardType, NSTIFFPboardType, nil];
      if ([[pboard availableTypeFromArray: types]
	    isEqualToString: NSRTFDPboardType])
	{
	  [self replaceRange: _selected_range
		withAttributedString: AUTORELEASE([[NSAttributedString alloc]
					 initWithRTFD:
					   [pboard dataForType: NSRTFDPboardType]
					 documentAttributes: NULL])];
	  return YES;
	}
      else if ([[pboard availableTypeFromArray: types]
		 isEqualToString: NSRTFPboardType])
	{
	  [self replaceRange: _selected_range
		withAttributedString: AUTORELEASE([[NSAttributedString alloc]
					 initWithRTF:
					   [pboard dataForType: NSRTFPboardType]
					 documentAttributes: NULL])];
	  return YES;
	}
      else if ([[pboard availableTypeFromArray: types]
		 isEqualToString: NSStringPboardType])
	{
	  [self insertText: [pboard stringForType: NSStringPboardType]];
	  return YES;
	}
    }
  else if ([self isRichText])
    {
      NSArray *types = [NSArray arrayWithObjects: NSRTFPboardType,
				NSStringPboardType, nil];
      if ([[pboard availableTypeFromArray: types]
	    isEqualToString: NSRTFPboardType])
	{
	  [self replaceRange: _selected_range
		withAttributedString: AUTORELEASE([[NSAttributedString alloc] 
					 initWithRTF:
					   [pboard dataForType: NSRTFPboardType]
					 documentAttributes: NULL])];
	  return YES;
	}
      else if ([[pboard availableTypeFromArray: types]
		 isEqualToString: NSStringPboardType])
	{
	  [self insertText: [pboard stringForType: NSStringPboardType]];
	  return YES;
	}
    }
  else	// plain text
    {
      NSArray *types = [NSArray arrayWithObjects: NSStringPboardType, nil];
      if ([[pboard availableTypeFromArray: types]
	    isEqualToString: NSStringPboardType])
	{
	  [self insertText: [pboard stringForType: NSStringPboardType]];
	  return YES;
	}
    }
  return NO;
}

- (BOOL) readSelectionFromPasteboard: (NSPasteboard*)pb
{
  return [self performPasteOperation: pb];
}


// central text deletion/backspace method
// (takes care of optimized redraw/ cursor positioning)
- (void) deleteRange: (NSRange) aRange
	   backspace: (BOOL) flag
{
  NSRange deleteRange;

  if (!aRange.length && !flag)
    return;

  if (!aRange.location && ! aRange.length)
    return;

  if (aRange.length)
    {
      deleteRange = aRange;
    }
  else
    {
      deleteRange = NSMakeRange (MAX (0, aRange.location - 1), 1);
    }

  [_textStorage deleteCharactersInRange: deleteRange];

  [self _editedRange: deleteRange withDelta: -deleteRange.length ];

  // ScrollView interaction
  [self sizeToFit];

  // move cursor <!> [self selectionRangeForProposedRange: ]
  [self setSelectedRange: NSMakeRange (deleteRange.location, 0)];

  // remember x for row - stable cursor movements
  _currentCursor = [self rectForCharacterIndex:
			   _selected_range.location].origin;
  // broadcast notification
  [[NSNotificationCenter defaultCenter]
    postNotificationName: NSTextDidChangeNotification
    object: self];
}

- (unsigned) characterIndexForPoint: (NSPoint) point
{
  return [_layoutManager characterIndexForPoint: point];
}

- (NSRect) rectForCharacterIndex: (unsigned) index
{
  return [_layoutManager rectForCharacterIndex: index];
}

- (void) _buildUpLayout
{
  if (_layoutManager == nil)
    _layoutManager = [[GSSimpleLayoutManager alloc]
		       initForText: self
		       withAttributedString: _textStorage];
  else
    [_layoutManager setAttributedString: _textStorage];
}

- (void) _editedRange: (NSRange) aRange
	    withDelta: (int) delta
{
  [_layoutManager _editedRange: aRange
		  withDelta: delta];
}

// Returns the currently used bounds for all the text
- (NSRect) _textBounds
{
  return [_layoutManager _textBounds];
}

- (void) drawRect: (NSRect) rect
    withSelection: (NSRange) selectedCharacterRange
{
  NSRange drawnRange;
  NSRange newRange;

  if (_tf.draws_background)
    {
      // clear area under text
      [[self backgroundColor] set];
      NSRectFill(rect);
    }

  drawnRange = [_layoutManager drawRectCharacters: rect];

  // We have to redraw the part of the selection that is inside
  // the redrawn lines
  newRange = NSIntersectionRange(selectedCharacterRange, drawnRange);
  // Was there any overlapping with the selection?
  if ((selectedCharacterRange.length &&
       NSLocationInRange(newRange.location, selectedCharacterRange)) ||
      (selectedCharacterRange.location == newRange.location))
    [self drawSelectionAsRange: newRange];
}

- (void) drawInsertionPointAtIndex: (unsigned) index
			     color: (NSColor*) color
			  turnedOn: (BOOL) flag
{
  NSRect drawRect  = [self rectForCharacterIndex: index];

  drawRect.size.width = 1;
  if (drawRect.size.height == 0)
    drawRect.size.height = 12;

  if (flag && color == nil)
    color = [NSColor blackColor];

  [self drawInsertionPointInRect: drawRect
	color: color
	turnedOn: flag];
}

- (void) drawSelectionAsRangeNoCaret: (NSRange) aRange
{
  if (aRange.length)
    {
      NSRect startRect = [self rectForCharacterIndex: aRange.location];
      NSRect endRect = [self rectForCharacterIndex: NSMaxRange (aRange)];
      float maxWidth = _frame.size.width;

      if (startRect.origin.y  == endRect.origin.y)
	{
	  // single line selection
	  NSHighlightRect (NSMakeRect (startRect.origin.x, startRect.origin.y,
				       endRect.origin.x - startRect.origin.x,
				       startRect.size.height));
	}
      else if (startRect.origin.y == endRect.origin.y - endRect.size.height)
	{
	  // two line selection

	  // first line
	  NSHighlightRect (NSMakeRect (startRect.origin.x, startRect.origin.y,
				       maxWidth - startRect.origin.x,
				       startRect.size.height));
	  // second line
	  NSHighlightRect (NSMakeRect (0, endRect.origin.y, endRect.origin.x,
				       endRect.size.height));

	}
      else
	{
	  //   3 Rects: multiline selection

	  // first line
	  NSHighlightRect (NSMakeRect (startRect.origin.x, startRect.origin.y,
				       maxWidth - startRect.origin.x,
				       startRect.size.height));
	  // intermediate lines
	  NSHighlightRect (NSMakeRect (0, NSMaxY(startRect),
				       maxWidth,
				       endRect.origin.y - NSMaxY (startRect)));
	  // last line
	  NSHighlightRect (NSMakeRect (0, endRect.origin.y, endRect.origin.x,
				       endRect.size.height));
	}
    }
}

- (void) drawSelectionAsRange: (NSRange) aRange
{
  if (aRange.length)
    {
      [self drawSelectionAsRangeNoCaret: aRange];
    }
  else
    {
      [self drawInsertionPointAtIndex: aRange.location
				color: [NSColor blackColor]
			     turnedOn: YES];
    }
}

// low level selection setting including delegation
- (void) setSelectedRangeNoDrawing: (NSRange)range
{
  //<!> ask delegate for selection validation
  _selected_range  = range;
  [self updateFontPanel];
#if 0
  [[NSNotificationCenter defaultCenter]
    postNotificationName: NSTextViewDidChangeSelectionNotification
    object: self
    userInfo: [NSDictionary dictionaryWithObjectsAndKeys:
		  NSStringFromRange (_selected_range),
		NSOldSelectedCharacterRange, nil]];
#endif
}
@end
