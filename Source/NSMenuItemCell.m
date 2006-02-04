/** <title>NSMenuItemCell</title>

   Copyright (C) 1999 Free Software Foundation, Inc.

   Author: Michael Hanni <mhanni@sprintmail.com>
   Date: 1999
   
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
   51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
*/ 

#include "config.h"
#include <Foundation/NSArray.h>
#include <Foundation/NSCoder.h>
#include <Foundation/NSDictionary.h>
#include <Foundation/NSException.h>
#include <Foundation/NSString.h>
#include <Foundation/NSNotification.h>
#include <Foundation/NSProcessInfo.h>
#include <Foundation/NSString.h>
#include <Foundation/NSUserDefaults.h>

#include "AppKit/NSColor.h"
#include "AppKit/NSFont.h"
#include "AppKit/NSGraphics.h"
#include "AppKit/NSImage.h"
#include "AppKit/NSMenu.h"
#include "AppKit/NSMenuItemCell.h"
#include "AppKit/NSMenuView.h"
#include "AppKit/NSParagraphStyle.h"
#include "GNUstepGUI/GSDrawFunctions.h"


@implementation NSMenuItemCell

static NSImage	*arrowImage = nil;	/* Cache arrow image.	*/


+ (void) initialize
{
  if (self == [NSMenuItemCell class])
    {
      [self setVersion: 2];
      arrowImage = [[NSImage imageNamed: @"NSMenuArrow"] copy];
    }
}

- (id) init
{
  [super init];
  _target = nil;
  _highlightsByMask = NSChangeBackgroundCellMask;
  _showAltStateMask = NSNoCellMask;
  _cell.image_position = NSNoImage;
  [self setAlignment: NSLeftTextAlignment];
  [self setFont: [NSFont menuFontOfSize: 0]];

  return self;
}

- (void) dealloc
{
  RELEASE (_menuItem);
  [super dealloc];
}

- (void) setHighlighted:(BOOL)flag
{
  _cell.is_highlighted = flag;
}

- (BOOL) isHighlighted
{
  // Same as in super class
  return _cell.is_highlighted;
}

- (void) setMenuItem: (NSMenuItem *)item
{
  ASSIGN (_menuItem, item);
  [self setEnabled: [_menuItem isEnabled]];
}

- (NSMenuItem *) menuItem
{
  return _menuItem;
}

- (void) setMenuView: (NSMenuView *)menuView
{
  /* The menu view is retaining us, we should not retain it.  */
  _menuView = menuView;
  /*
   * Determine whether we have horizontal or vertical layout and adjust.
   */
  if ([_menuView isHorizontal])
    {
      _horizontalMenu = YES;
      [self setAlignment: NSCenterTextAlignment];
    }
  else
    {
      _horizontalMenu = NO;
      [self setAlignment: NSLeftTextAlignment];
    }
}

- (NSMenuView *) menuView
{
  return _menuView;
}

- (void) calcSize
{
  NSSize   componentSize;
  NSImage *anImage = nil;
  float    neededMenuItemHeight = 20;
 
  // Check if _mcell_belongs_to_popupbutton = NO while cell owned by 
  // popup button. FIXME
  if (!_mcell_belongs_to_popupbutton && [[_menuView menu] _ownedByPopUp])
    {
      _mcell_belongs_to_popupbutton = YES;
      [self setImagePosition: NSImageRight];
    }

  // State Image
  if ([_menuItem changesState])
    {
      // NSOnState
      if ([_menuItem onStateImage])
        componentSize = [[_menuItem onStateImage] size];
      else
      	componentSize = NSMakeSize(0,0);
      _stateImageWidth = componentSize.width;
      if (componentSize.height > neededMenuItemHeight)
	neededMenuItemHeight = componentSize.height;

      // NSOffState
      if ([_menuItem offStateImage])
        componentSize = [[_menuItem offStateImage] size];
      else
      	componentSize = NSMakeSize(0,0);
      if (componentSize.width > _stateImageWidth)
	_stateImageWidth = componentSize.width;
      if (componentSize.height > neededMenuItemHeight)
	neededMenuItemHeight = componentSize.height;

      // NSMixedState
      if ([_menuItem mixedStateImage])
        componentSize = [[_menuItem mixedStateImage] size];
      else
      	componentSize = NSMakeSize(0,0);
      if (componentSize.width > _stateImageWidth)
	_stateImageWidth = componentSize.width;
      if (componentSize.height > neededMenuItemHeight)
	neededMenuItemHeight = componentSize.height;
    }
  else
    {
      _stateImageWidth = 0.0;
    }

  // Image
  if ((anImage = [_menuItem image]) && _cell.image_position == NSNoImage)
    [self setImagePosition: NSImageLeft];
  if (anImage)
    {
      componentSize = [anImage size];
      _imageWidth = componentSize.width;
      if (componentSize.height > neededMenuItemHeight)
	neededMenuItemHeight = componentSize.height;
    }
  else
    {
      _imageWidth = 0.0;
    }

  // Title and Key Equivalent
  componentSize = [self _sizeText: [_menuItem title]];
  _titleWidth = componentSize.width;
  if (componentSize.height > neededMenuItemHeight)
    neededMenuItemHeight = componentSize.height;
  componentSize = [self _sizeText: [_menuItem keyEquivalent]];
  _keyEquivalentWidth = componentSize.width;
  if (componentSize.height > neededMenuItemHeight)
    neededMenuItemHeight = componentSize.height;

  // Submenu Arrow
  if ([_menuItem hasSubmenu])
    {
      componentSize = [arrowImage size];
      _keyEquivalentWidth = componentSize.width;
      if (componentSize.height > neededMenuItemHeight)
	neededMenuItemHeight = componentSize.height;
    }

  // Cache definitive height
  _menuItemHeight = neededMenuItemHeight;

  // At the end we set sizing to NO.
  _needs_sizing = NO;
}

- (void) setNeedsSizing:(BOOL)flag
{
  _needs_sizing = flag;
}

- (BOOL) needsSizing
{
  return _needs_sizing;
}

- (float) imageWidth
{
  if (_needs_sizing)
    [self calcSize];

  return _imageWidth;
}

- (float) titleWidth
{
  if (_needs_sizing)
    [self calcSize];

  return _titleWidth;
}

- (float) keyEquivalentWidth
{
  if (_needs_sizing)
    [self calcSize];

  return _keyEquivalentWidth;
}

- (float) stateImageWidth
{
  if (_needs_sizing)
    [self calcSize];

  return _stateImageWidth;
}

//
// Sizes for drawing taking into account NSMenuView adjustments.
//
- (NSRect) imageRectForBounds:(NSRect)cellFrame
{
  if (_horizontalMenu == YES)
    {
      switch (_cell.image_position)
	{
	  case NSNoImage:
	    cellFrame = NSZeroRect;
	    break;
	    
	  case NSImageOnly:
	  case NSImageOverlaps:
	    break;
	    
	  case NSImageLeft:
	    cellFrame.origin.x  += 4.; // _horizontalEdgePad
	    cellFrame.size.width = _imageWidth;
	    break;
	
	  case NSImageRight:
	    cellFrame.origin.x  += _titleWidth;
	    cellFrame.size.width = _imageWidth;
	    break;
	   
	  case NSImageBelow:
	    cellFrame.size.height /= 2;
	    break;
	    
	  case NSImageAbove:
	    cellFrame.size.height /= 2;
	    cellFrame.origin.y += cellFrame.size.height;
	    break;
	}
    }
  else
    {
      if (_mcell_belongs_to_popupbutton && _cell.image_position)
	{
	  // Special case: draw image on the extreme right 
	  cellFrame.origin.x  += cellFrame.size.width - _imageWidth - 4;
	  cellFrame.size.width = _imageWidth;
	  return cellFrame;
	}

      // Calculate the image part of cell frame from NSMenuView
      cellFrame.origin.x  += [_menuView imageAndTitleOffset];
      cellFrame.size.width = [_menuView imageAndTitleWidth];

      switch (_cell.image_position)
	{
	  case NSNoImage: 
	    cellFrame = NSZeroRect;
	    break;

	  case NSImageOnly:
	  case NSImageOverlaps:
	    break;

	  case NSImageLeft:
	    cellFrame.size.width = _imageWidth;
	    break;

	  case NSImageRight:
	    cellFrame.origin.x  += _titleWidth + GSCellTextImageXDist;
	    cellFrame.size.width = _imageWidth;
	    break;

	  case NSImageBelow: 
	    cellFrame.size.height /= 2;
	    break;

	  case NSImageAbove: 
	    cellFrame.size.height /= 2;
	    cellFrame.origin.y += cellFrame.size.height;
	    break;
	}
    }
  return cellFrame;
}

- (NSRect) keyEquivalentRectForBounds:(NSRect)cellFrame
{
  // Calculate the image part of cell frame from NSMenuView
  cellFrame.origin.x  += [_menuView keyEquivalentOffset];
  cellFrame.size.width = [_menuView keyEquivalentWidth];

  return cellFrame;
}

- (NSRect) stateImageRectForBounds:(NSRect)cellFrame
{
  // Calculate the image part of cell frame from NSMenuView
  cellFrame.origin.x  += [_menuView stateImageOffset];
  cellFrame.size.width = [_menuView stateImageWidth];

  return cellFrame;
}

- (NSRect) titleRectForBounds:(NSRect)cellFrame
{
  if (_horizontalMenu == YES)
    {
      /* This adjust will center us within the menubar. */

      cellFrame.size.height -= 2;

      switch (_cell.image_position)
	{
	  case NSNoImage:
	  case NSImageOverlaps:
	    break;
      
	  case NSImageOnly:
	    cellFrame = NSZeroRect;
	    break;
	
	  case NSImageLeft:
	    cellFrame.origin.x  += _imageWidth + GSCellTextImageXDist + 4;
	    cellFrame.size.width = _titleWidth;
	    break;
	    
	  case NSImageRight:
	    cellFrame.size.width = _titleWidth;
	    break;
		     
	  case NSImageBelow:
	    cellFrame.size.height /= 2;
	    cellFrame.origin.y += cellFrame.size.height;
	    break;

	  case NSImageAbove:
	    cellFrame.size.height /= 2;
	    break;
	}
    }
  else
    {
      // Calculate the image part of cell frame from NSMenuView
      cellFrame.origin.x  += [_menuView imageAndTitleOffset];
      cellFrame.size.width = [_menuView imageAndTitleWidth];

      switch (_cell.image_position)
	{
	  case NSNoImage:
	  case NSImageOverlaps:
	    break;

	  case NSImageOnly:
	    cellFrame = NSZeroRect;
	    break;

	  case NSImageLeft:
	    cellFrame.origin.x  += _imageWidth + GSCellTextImageXDist;
	    cellFrame.size.width = _titleWidth;
	    break;

	  case NSImageRight:
	    cellFrame.size.width = _titleWidth;
	    break;

	  case NSImageBelow:
	    cellFrame.size.height /= 2;
	    cellFrame.origin.y += cellFrame.size.height;
	    break;

	  case NSImageAbove:
	    cellFrame.size.height /= 2;
	    break;
	}
    }
  return cellFrame;
}

//
// Drawing.
//
- (void) drawBorderAndBackgroundWithFrame: (NSRect)cellFrame
				  inView: (NSView *)controlView
{
  if (_horizontalMenu == YES)
    return;

  if (!_cell.is_bordered)
    return;

  if (_cell.is_highlighted && (_highlightsByMask & NSPushInCellMask))
    {
      [GSDrawFunctions drawGrayBezel: cellFrame : NSZeroRect];
    }
  else
    {
      [GSDrawFunctions drawButton: cellFrame : NSZeroRect];
    }
}

- (void) drawImageWithFrame: (NSRect)cellFrame
		     inView: (NSView *)controlView
{
  NSSize	size;
  NSPoint	position;

  cellFrame = [self imageRectForBounds: cellFrame];
  size = [_imageToDisplay size];
  position.x = MAX(NSMidX(cellFrame) - (size.width/2.), 0.);
  position.y = MAX(NSMidY(cellFrame) - (size.height/2.), 0.);
  /*
   * Images are always drawn with their bottom-left corner at the origin
   * so we must adjust the position to take account of a flipped view.
   */
  if ([controlView isFlipped])
    position.y += size.height;

  [_imageToDisplay compositeToPoint: position operation: NSCompositeSourceOver];
}

- (void) drawKeyEquivalentWithFrame:(NSRect)cellFrame
			    inView:(NSView *)controlView
{
  cellFrame = [self keyEquivalentRectForBounds: cellFrame];

  if ([_menuItem hasSubmenu])
    {
      NSSize	size;
      NSPoint	position;

      size = [arrowImage size];
      position.x = cellFrame.origin.x + cellFrame.size.width - size.width;
      position.y = MAX(NSMidY(cellFrame) - (size.height/2.), 0.);
      /*
       * Images are always drawn with their bottom-left corner at the origin
       * so we must adjust the position to take account of a flipped view.
       */
      if ([controlView isFlipped])
	position.y += size.height;

      [arrowImage compositeToPoint: position operation: NSCompositeSourceOver];
    }
  /* FIXME/TODO here - decide a consistent policy for images.
   *
   * The reason of the following code is that we draw the key
   * equivalent, but not if we are a popup button and are displaying
   * an image (the image is displayed in the title or selected entry
   * in the popup, it's the small square on the right). In that case,
   * the image will be drawn in the same position where the key
   * equivalent would be, so we do not display the key equivalent,
   * else they would be displayed one over the other one.
   */
  else if (![[_menuView menu] _ownedByPopUp])
    {    
      [self _drawText: [_menuItem keyEquivalent] inFrame: cellFrame];
    }
  else if (_imageToDisplay == nil)
    {
      [self _drawText: [_menuItem keyEquivalent] inFrame: cellFrame];
    }
}


- (void) drawSeparatorItemWithFrame:(NSRect)cellFrame
			    inView:(NSView *)controlView
{
  // FIXME: This only has sense in MacOS or Windows interface styles.
  // Maybe somebody wants to support this (Lazaro).
}

- (void) drawStateImageWithFrame: (NSRect)cellFrame
			  inView: (NSView*)controlView
{
  NSSize	size;
  NSPoint	position;
  NSImage	*imageToDisplay;

  switch ([_menuItem state])
    {
      case NSOnState:
	imageToDisplay = [_menuItem onStateImage];
	break;

      case NSMixedState:
	imageToDisplay = [_menuItem mixedStateImage];
	break;

      case NSOffState:
      default:
	imageToDisplay = [_menuItem offStateImage];
	break;
    }

  if (imageToDisplay == nil)
    {
      return;
    }
  
  size = [imageToDisplay size];
  cellFrame = [self stateImageRectForBounds: cellFrame];
  position.x = MAX(NSMidX(cellFrame) - (size.width/2.),0.);
  position.y = MAX(NSMidY(cellFrame) - (size.height/2.),0.);
  /*
   * Images are always drawn with their bottom-left corner at the origin
   * so we must adjust the position to take account of a flipped view.
   */
  if ([controlView isFlipped])
    {
      position.y += size.height;
    }
  
  [imageToDisplay compositeToPoint: position operation: NSCompositeSourceOver];
}

- (void) drawTitleWithFrame:(NSRect)cellFrame
		    inView:(NSView *)controlView
{
  if (_horizontalMenu == YES)
    {
      id value = [NSMutableParagraphStyle defaultParagraphStyle];
      NSDictionary *attr;
      NSRect cf = [self titleRectForBounds: cellFrame];

      if (!_imageWidth)
	[value setAlignment: NSCenterTextAlignment];

      attr = [[NSDictionary alloc] initWithObjectsAndKeys:
	value, NSParagraphStyleAttributeName,
	_font, NSFontAttributeName,
	[NSColor controlTextColor], NSForegroundColorAttributeName,
	nil];

      if ([_menuItem isEnabled])
	_cell.is_disabled = NO;
      else
	_cell.is_disabled = YES;

      [[_menuItem title] drawInRect: cf withAttributes: attr];

      RELEASE(attr);
    }
  else
    {
      [self _drawText: [_menuItem title]
	      inFrame: [self titleRectForBounds: cellFrame]];
    }
}

- (void) drawWithFrame: (NSRect)cellFrame inView: (NSView*)controlView
{
  // Save last view drawn to
  if (_control_view != controlView)
    _control_view = controlView;

  // Transparent buttons never draw
  if (_buttoncell_is_transparent)
    return;

  // Do nothing if cell's frame rect is zero
  if (NSIsEmptyRect(cellFrame))
    return;

  // Draw the border if needed
  [self drawBorderAndBackgroundWithFrame: cellFrame inView: controlView];

  [self drawInteriorWithFrame: cellFrame inView: controlView];
}

- (void) drawInteriorWithFrame: (NSRect)cellFrame inView: (NSView*)controlView
{
  unsigned  mask;

  // Transparent buttons never draw
  if (_buttoncell_is_transparent)
    return;

  if (_horizontalMenu == YES)
    {
      NSColor *backgroundColor = nil;

      cellFrame = [self drawingRectForBounds: cellFrame];

      if (_cell.is_highlighted)
	{
	  mask = _highlightsByMask;

	  if (_cell.state)
	    mask &= ~_showAltStateMask;
	}
      else if (_cell.state)
	mask = _showAltStateMask;
      else
	mask = NSNoCellMask;

      /* 
       * Determine the background color and cache it in an ivar so that the
       * low-level drawing methods don't need to do it again.
       */
      if (mask & (NSChangeGrayCellMask | NSChangeBackgroundCellMask))
	{
	  backgroundColor = [NSColor selectedMenuItemColor];
	}
      if (backgroundColor == nil)
	backgroundColor = [NSColor controlBackgroundColor];

      // Set cell's background color
      [backgroundColor set];
      NSRectFill(cellFrame);
      if (mask & NSContentsCellMask)
	{
	  _imageToDisplay = _altImage;
	  if (!_imageToDisplay)
	    _imageToDisplay = [_menuItem image];
	  _titleToDisplay = _altContents;
	  if (_titleToDisplay == nil || [_titleToDisplay isEqual: @""])
	    _titleToDisplay = [_menuItem title];
	}
      else
	{
	  _imageToDisplay = [_menuItem image];
	  _titleToDisplay = [_menuItem title];
	}
       
      if (_imageToDisplay)
	{
	  _imageWidth = [_imageToDisplay size].width;
	  [self setImagePosition: NSImageLeft];
	}
	  
      // Draw the image
      if (_imageWidth > 0)
	[self drawImageWithFrame: cellFrame inView: controlView];
	 
      // Draw the title
      if (_titleWidth > 0)
	[self drawTitleWithFrame: cellFrame inView: controlView];
    }
  else
    {
      cellFrame = [self drawingRectForBounds: cellFrame];

      if (_cell.is_highlighted)
	{
	  mask = _highlightsByMask;

	  if (_cell.state)
	    mask &= ~_showAltStateMask;
	}
      else if (_cell.state)
	mask = _showAltStateMask;
      else
	mask = NSNoCellMask;

      // pushed in buttons contents are displaced to the bottom right 1px
      if (_cell.is_bordered && (mask & NSPushInCellMask))
	{
	  cellFrame = NSOffsetRect(cellFrame, 1., [controlView isFlipped] ? 1. : -1.);
	}

      /*
       * Determine the background color and cache it in an ivar so that the
       * low-level drawing methods don't need to do it again.
       */
      if (mask & (NSChangeGrayCellMask | NSChangeBackgroundCellMask))
	{
	  _backgroundColor = [NSColor selectedMenuItemColor];
	}
      if (_backgroundColor == nil)
	_backgroundColor = [NSColor controlBackgroundColor];

      // Set cell's background color
      [_backgroundColor set];
      NSRectFill(cellFrame);

      /*
       * Determine the image and the title that will be
       * displayed. If the NSContentsCellMask is set the
       * image and title are swapped only if state is 1 or
       * if highlighting is set (when a button is pushed it's
       * content is changed to the face of reversed state).
       * The results are saved in two ivars for use in other
       * drawing methods.
       */
      if (mask & NSContentsCellMask)
	{
	  _imageToDisplay = _altImage;
	  if (!_imageToDisplay)
	    _imageToDisplay = [_menuItem image];
	  _titleToDisplay = _altContents;
	  if (_titleToDisplay == nil || [_titleToDisplay isEqual: @""])
	    _titleToDisplay = [_menuItem title];
	}
      else
	{
	  _imageToDisplay = [_menuItem image];
	  _titleToDisplay = [_menuItem title];
	}

      if (_imageToDisplay)
	{
	  _imageWidth = [_imageToDisplay size].width;
	}

      // Draw the state image
      if (_stateImageWidth > 0)
	[self drawStateImageWithFrame: cellFrame inView: controlView];

      // Draw the image
      if (_imageWidth > 0)
	[self drawImageWithFrame: cellFrame inView: controlView];

      // Draw the title
      if (_titleWidth > 0)
	[self drawTitleWithFrame: cellFrame inView: controlView];

      // Draw the key equivalent
      if (_keyEquivalentWidth > 0)
	[self drawKeyEquivalentWithFrame: cellFrame inView: controlView];

      _backgroundColor = nil;
    }
}

- (NSRect) drawingRectForBounds: (NSRect)theRect
{
  if (_horizontalMenu == YES)
    {
      return NSMakeRect (theRect.origin.x, theRect.origin.y + 2,
	theRect.size.width, theRect.size.height - 2);
    }
  else
    {
      return [super drawingRectForBounds: theRect];
    }
}

//
// NSCopying protocol
//
- (id) copyWithZone: (NSZone*)zone
{
  NSMenuItemCell *c = [super copyWithZone: zone];

  if (_menuItem)
    c->_menuItem = [_menuItem copyWithZone: zone];

  /* We do not copy _menuView, because _menuView owns the old cell,
     but not the new one!  _menuView knows nothing about c.  If we copy
     the pointer to _menuView into c, then that pointer might become
     invalid at any point in time (it never becomes invalid for the original
     cell because _menuView will call [originalCell setMenuView: nil]
     when it's being deallocated.  But it will not do the same for c, because
     it doesn't even know that c exists!)  */
  c->_menuView = nil;

  return c;
}

/*
 * NSCoding protocol
 *
 * Normally unused since the NSMenu encodes/decodes the NSMenuItems, but
 * not the NSMenuItemCells.
 */
- (void) encodeWithCoder: (NSCoder*)aCoder
{
  [super encodeWithCoder: aCoder];

  [aCoder encodeConditionalObject: _menuItem];
}

- (id) initWithCoder: (NSCoder*)aDecoder
{
  self = [super initWithCoder: aDecoder];

  if ([aDecoder allowsKeyedCoding])
    {
      [self setMenuItem: [aDecoder decodeObjectForKey: @"NSMenuItem"]];
    }
  else
    {
      ASSIGN (_menuItem, [aDecoder decodeObject]);

      if ([aDecoder versionForClassName: @"NSMenuItemCell"] < 2)
        {
	  /* In version 1, we used to encode the _menuView here.  */
	  [aDecoder decodeObject];
	}
    }
  _needs_sizing = YES;

  return self;
}

@end
