//========================================================================
// GLFW 3.4 macOS - www.glfw.org
//------------------------------------------------------------------------
// Copyright (c) 2009-2019 Camilla Löwy <elmindreda@glfw.org>
//
// This software is provided 'as-is', without any express or implied
// warranty. In no event will the authors be held liable for any damages
// arising from the use of this software.
//
// Permission is granted to anyone to use this software for any purpose,
// including commercial applications, and to alter it and redistribute it
// freely, subject to the following restrictions:
//
// 1. The origin of this software must not be misrepresented; you must not
//    claim that you wrote the original software. If you use this software
//    in a product, an acknowledgment in the product documentation would
//    be appreciated but is not required.
//
// 2. Altered source versions must be plainly marked as such, and must not
//    be misrepresented as being the original software.
//
// 3. This notice may not be removed or altered from any source
//    distribution.
//
//========================================================================
// It is fine to use C99 in this file because it will not be built with VS
//========================================================================

#include "internal.h"

#include <float.h>
#include <string.h>

#if NEW_APPLE

// Returns the style mask corresponding to the window settings
//
static NSUInteger getStyleMask(_GLFWwindow* window)
{
    NSUInteger styleMask = NSWindowStyleMaskMiniaturizable;

    if (window->monitor || !window->decorated)
        styleMask |= NSWindowStyleMaskBorderless;
    else
    {
        styleMask |= NSWindowStyleMaskTitled |
                     NSWindowStyleMaskClosable;

        if (window->resizable)
            styleMask |= NSWindowStyleMaskResizable;
    }

    return styleMask;
}

// Returns whether the cursor is in the content area of the specified window
//
static GLFWbool cursorInContentArea(_GLFWwindow* window)
{
    const NSPoint pos = [window->ns.object mouseLocationOutsideOfEventStream];
    return [window->ns.view mouse:pos inRect:[window->ns.view frame]];
}

// Hides the cursor if not already hidden
//
static void hideCursor(_GLFWwindow* window)
{
    if (!_glfw.ns.cursorHidden)
    {
        [NSCursor hide];
        _glfw.ns.cursorHidden = GLFW_TRUE;
    }
}

// Shows the cursor if not already shown
//
static void showCursor(_GLFWwindow* window)
{
    if (_glfw.ns.cursorHidden)
    {
        [NSCursor unhide];
        _glfw.ns.cursorHidden = GLFW_FALSE;
    }
}

// Updates the cursor image according to its cursor mode
//
static void updateCursorImage(_GLFWwindow* window)
{
    if (window->cursorMode == GLFW_CURSOR_NORMAL)
    {
        showCursor(window);

        if (window->cursor)
            [(NSCursor*) window->cursor->ns.object set];
        else
            [[NSCursor arrowCursor] set];
    }
    else
        hideCursor(window);
}

// Apply chosen cursor mode to a focused window
//
static void updateCursorMode(_GLFWwindow* window)
{
    if (window->cursorMode == GLFW_CURSOR_DISABLED)
    {
        _glfw.ns.disabledCursorWindow = window;
        _glfwGetCursorPosCocoa(window,
                               &_glfw.ns.restoreCursorPosX,
                               &_glfw.ns.restoreCursorPosY);
        _glfwCenterCursorInContentArea(window);
        CGAssociateMouseAndMouseCursorPosition(false);
    }
    else if (_glfw.ns.disabledCursorWindow == window)
    {
        _glfw.ns.disabledCursorWindow = NULL;
        _glfwSetCursorPosCocoa(window,
                               _glfw.ns.restoreCursorPosX,
                               _glfw.ns.restoreCursorPosY);
        // NOTE: The matching CGAssociateMouseAndMouseCursorPosition call is
        //       made in _glfwSetCursorPosCocoa as part of a workaround
    }

    if (cursorInContentArea(window))
        updateCursorImage(window);
}

// Make the specified window and its video mode active on its monitor
//
static void acquireMonitor(_GLFWwindow* window)
{
    _glfwSetVideoModeCocoa(window->monitor, &window->videoMode);
    const CGRect bounds = CGDisplayBounds(window->monitor->ns.displayID);
    const NSRect frame = NSMakeRect(bounds.origin.x,
                                    _glfwTransformYCocoa(bounds.origin.y + bounds.size.height - 1),
                                    bounds.size.width,
                                    bounds.size.height);

    [window->ns.object setFrame:frame display:YES];

    _glfwInputMonitorWindow(window->monitor, window);
}

// Remove the window and restore the original video mode
//
static void releaseMonitor(_GLFWwindow* window)
{
    if (window->monitor->window != window)
        return;

    _glfwInputMonitorWindow(window->monitor, NULL);
    _glfwRestoreVideoModeCocoa(window->monitor);
}

// Translates macOS key modifiers into GLFW ones
//
static int translateFlags(NSUInteger flags)
{
    int mods = 0;

    if (flags & NSEventModifierFlagShift)
        mods |= GLFW_MOD_SHIFT;
    if (flags & NSEventModifierFlagControl)
        mods |= GLFW_MOD_CONTROL;
    if (flags & NSEventModifierFlagOption)
        mods |= GLFW_MOD_ALT;
    if (flags & NSEventModifierFlagCommand)
        mods |= GLFW_MOD_SUPER;
    if (flags & NSEventModifierFlagCapsLock)
        mods |= GLFW_MOD_CAPS_LOCK;

    return mods;
}

// Translates a macOS keycode to a GLFW keycode
//
static int translateKey(unsigned int key)
{
    if (key >= sizeof(_glfw.ns.keycodes) / sizeof(_glfw.ns.keycodes[0]))
        return GLFW_KEY_UNKNOWN;

    return _glfw.ns.keycodes[key];
}

// Translate a GLFW keycode to a Cocoa modifier flag
//
static NSUInteger translateKeyToModifierFlag(int key)
{
    switch (key)
    {
        case GLFW_KEY_LEFT_SHIFT:
        case GLFW_KEY_RIGHT_SHIFT:
            return NSEventModifierFlagShift;
        case GLFW_KEY_LEFT_CONTROL:
        case GLFW_KEY_RIGHT_CONTROL:
            return NSEventModifierFlagControl;
        case GLFW_KEY_LEFT_ALT:
        case GLFW_KEY_RIGHT_ALT:
            return NSEventModifierFlagOption;
        case GLFW_KEY_LEFT_SUPER:
        case GLFW_KEY_RIGHT_SUPER:
            return NSEventModifierFlagCommand;
        case GLFW_KEY_CAPS_LOCK:
            return NSEventModifierFlagCapsLock;
    }

    return 0;
}

// Defines a constant for empty ranges in NSTextInputClient
//
static const NSRange kEmptyRange = { NSNotFound, 0 };

//------------------------------------------------------------------------
// Delegate for window related notifications
//------------------------------------------------------------------------
@interface GLFWWindowDelegate : NSObject
{
    _GLFWwindow* window;
}

- (instancetype)initWithGlfwWindow:(_GLFWwindow *)initWindow;

@end

@implementation GLFWWindowDelegate

- (instancetype)initWithGlfwWindow:(_GLFWwindow *)initWindow
{
    self = [super init];
    if (self != nil)
        window = initWindow;

    return self;
}

- (BOOL)windowShouldClose:(id)sender
{
    _glfwInputWindowCloseRequest(window);
    return NO;
}

- (void)windowDidResize:(NSNotification *)notification
{
    if (window->context.source == GLFW_NATIVE_CONTEXT_API)
        [window->context.nsgl.object update];

    if (_glfw.ns.disabledCursorWindow == window)
        _glfwCenterCursorInContentArea(window);

    const int maximized = [window->ns.object isZoomed];
    if (window->ns.maximized != maximized)
    {
        window->ns.maximized = maximized;
        _glfwInputWindowMaximize(window, maximized);
    }

    const NSRect contentRect = [window->ns.view frame];
    const NSRect fbRect = [window->ns.view convertRectToBacking:contentRect];

    if (fbRect.size.width != window->ns.fbWidth ||
        fbRect.size.height != window->ns.fbHeight)
    {
        window->ns.fbWidth  = fbRect.size.width;
        window->ns.fbHeight = fbRect.size.height;
        _glfwInputFramebufferSize(window, fbRect.size.width, fbRect.size.height);
    }

    if (contentRect.size.width != window->ns.width ||
        contentRect.size.height != window->ns.height)
    {
        window->ns.width  = contentRect.size.width;
        window->ns.height = contentRect.size.height;
        _glfwInputWindowSize(window, contentRect.size.width, contentRect.size.height);
    }
}

- (void)windowDidMove:(NSNotification *)notification
{
    if (window->context.source == GLFW_NATIVE_CONTEXT_API)
        [window->context.nsgl.object update];

    if (_glfw.ns.disabledCursorWindow == window)
        _glfwCenterCursorInContentArea(window);

    int x, y;
    _glfwGetWindowPosCocoa(window, &x, &y);
    _glfwInputWindowPos(window, x, y);
}

- (void)windowDidMiniaturize:(NSNotification *)notification
{
    if (window->monitor)
        releaseMonitor(window);

    _glfwInputWindowIconify(window, GLFW_TRUE);
}

- (void)windowDidDeminiaturize:(NSNotification *)notification
{
    if (window->monitor)
        acquireMonitor(window);

    _glfwInputWindowIconify(window, GLFW_FALSE);
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
    if (_glfw.ns.disabledCursorWindow == window)
        _glfwCenterCursorInContentArea(window);

    _glfwInputWindowFocus(window, GLFW_TRUE);
    updateCursorMode(window);
}

- (void)windowDidResignKey:(NSNotification *)notification
{
    if (window->monitor && window->autoIconify)
        _glfwIconifyWindowCocoa(window);

    _glfwInputWindowFocus(window, GLFW_FALSE);
}

- (void)windowDidChangeOcclusionState:(NSNotification* )notification
{
    if ([window->ns.object occlusionState] & NSWindowOcclusionStateVisible)
        window->ns.occluded = GLFW_FALSE;
    else
        window->ns.occluded = GLFW_TRUE;
}

@end

//------------------------------------------------------------------------
// Content view class for the GLFW window
//------------------------------------------------------------------------
@interface GLFWContentView : NSView <NSTextInputClient>
{
    _GLFWwindow* window;
    NSTrackingArea* trackingArea;
    NSMutableAttributedString* markedText;
}

- (instancetype)initWithGlfwWindow:(_GLFWwindow *)initWindow;

@end

@implementation GLFWContentView

- (instancetype)initWithGlfwWindow:(_GLFWwindow *)initWindow
{
    self = [super init];
    if (self != nil)
    {
        window = initWindow;
        trackingArea = nil;
        markedText = [[NSMutableAttributedString alloc] init];

        [self updateTrackingAreas];
        [self registerForDraggedTypes:@[NSPasteboardTypeURL]];
    }

    return self;
}

- (void)dealloc
{
    [trackingArea release];
    [markedText release];
    [super dealloc];
}

- (BOOL)isOpaque
{
    return [window->ns.object isOpaque];
}

- (BOOL)canBecomeKeyView
{
    return YES;
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (BOOL)wantsUpdateLayer
{
    return YES;
}

- (void)updateLayer
{
    if (window->context.source == GLFW_NATIVE_CONTEXT_API)
        [window->context.nsgl.object update];

    _glfwInputWindowDamage(window);
}

- (void)cursorUpdate:(NSEvent *)event
{
    updateCursorImage(window);
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
    return YES;
}

- (void)mouseDown:(NSEvent *)event
{
    _glfwInputMouseClick(window,
                         GLFW_MOUSE_BUTTON_LEFT,
                         GLFW_PRESS,
                         translateFlags([event modifierFlags]));
}

- (void)mouseDragged:(NSEvent *)event
{
    [self mouseMoved:event];
}

- (void)mouseUp:(NSEvent *)event
{
    _glfwInputMouseClick(window,
                         GLFW_MOUSE_BUTTON_LEFT,
                         GLFW_RELEASE,
                         translateFlags([event modifierFlags]));
}

- (void)mouseMoved:(NSEvent *)event
{
    if (window->cursorMode == GLFW_CURSOR_DISABLED)
    {
        const double dx = [event deltaX] - window->ns.cursorWarpDeltaX;
        const double dy = [event deltaY] - window->ns.cursorWarpDeltaY;

        _glfwInputCursorPos(window,
                            window->virtualCursorPosX + dx,
                            window->virtualCursorPosY + dy);
    }
    else
    {
        const NSRect contentRect = [window->ns.view frame];
        // NOTE: The returned location uses base 0,1 not 0,0
        const NSPoint pos = [event locationInWindow];

        _glfwInputCursorPos(window, pos.x, contentRect.size.height - pos.y);
    }

    window->ns.cursorWarpDeltaX = 0;
    window->ns.cursorWarpDeltaY = 0;
}

- (void)rightMouseDown:(NSEvent *)event
{
    _glfwInputMouseClick(window,
                         GLFW_MOUSE_BUTTON_RIGHT,
                         GLFW_PRESS,
                         translateFlags([event modifierFlags]));
}

- (void)rightMouseDragged:(NSEvent *)event
{
    [self mouseMoved:event];
}

- (void)rightMouseUp:(NSEvent *)event
{
    _glfwInputMouseClick(window,
                         GLFW_MOUSE_BUTTON_RIGHT,
                         GLFW_RELEASE,
                         translateFlags([event modifierFlags]));
}

- (void)otherMouseDown:(NSEvent *)event
{
    _glfwInputMouseClick(window,
                         (int) [event buttonNumber],
                         GLFW_PRESS,
                         translateFlags([event modifierFlags]));
}

- (void)otherMouseDragged:(NSEvent *)event
{
    [self mouseMoved:event];
}

- (void)otherMouseUp:(NSEvent *)event
{
    _glfwInputMouseClick(window,
                         (int) [event buttonNumber],
                         GLFW_RELEASE,
                         translateFlags([event modifierFlags]));
}

- (void)mouseExited:(NSEvent *)event
{
    if (window->cursorMode == GLFW_CURSOR_HIDDEN)
        showCursor(window);

    _glfwInputCursorEnter(window, GLFW_FALSE);
}

- (void)mouseEntered:(NSEvent *)event
{
    if (window->cursorMode == GLFW_CURSOR_HIDDEN)
        hideCursor(window);

    _glfwInputCursorEnter(window, GLFW_TRUE);
}

- (void)viewDidChangeBackingProperties
{
    const NSRect contentRect = [window->ns.view frame];
    const NSRect fbRect = [window->ns.view convertRectToBacking:contentRect];
    const float xscale = fbRect.size.width / contentRect.size.width;
    const float yscale = fbRect.size.height / contentRect.size.height;

    if (xscale != window->ns.xscale || yscale != window->ns.yscale)
    {
        if (window->ns.retina && window->ns.layer)
            [window->ns.layer setContentsScale:[window->ns.object backingScaleFactor]];

        window->ns.xscale = xscale;
        window->ns.yscale = yscale;
        _glfwInputWindowContentScale(window, xscale, yscale);
    }

    if (fbRect.size.width != window->ns.fbWidth ||
        fbRect.size.height != window->ns.fbHeight)
    {
        window->ns.fbWidth  = fbRect.size.width;
        window->ns.fbHeight = fbRect.size.height;
        _glfwInputFramebufferSize(window, fbRect.size.width, fbRect.size.height);
    }
}

- (void)drawRect:(NSRect)rect
{
    _glfwInputWindowDamage(window);
}

- (void)updateTrackingAreas
{
    if (trackingArea != nil)
    {
        [self removeTrackingArea:trackingArea];
        [trackingArea release];
    }

    const NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited |
                                          NSTrackingActiveInKeyWindow |
                                          NSTrackingEnabledDuringMouseDrag |
                                          NSTrackingCursorUpdate |
                                          NSTrackingInVisibleRect |
                                          NSTrackingAssumeInside;

    trackingArea = [[NSTrackingArea alloc] initWithRect:[self bounds]
                                                options:options
                                                  owner:self
                                               userInfo:nil];

    [self addTrackingArea:trackingArea];
    [super updateTrackingAreas];
}

- (void)keyDown:(NSEvent *)event
{
    const int key = translateKey([event keyCode]);
    const int mods = translateFlags([event modifierFlags]);

    _glfwInputKey(window, key, [event keyCode], GLFW_PRESS, mods);

    [self interpretKeyEvents:@[event]];
}

- (void)flagsChanged:(NSEvent *)event
{
    int action;
    const unsigned int modifierFlags =
        [event modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;
    const int key = translateKey([event keyCode]);
    const int mods = translateFlags(modifierFlags);
    const NSUInteger keyFlag = translateKeyToModifierFlag(key);

    if (keyFlag & modifierFlags)
    {
        if (window->keys[key] == GLFW_PRESS)
            action = GLFW_RELEASE;
        else
            action = GLFW_PRESS;
    }
    else
        action = GLFW_RELEASE;

    _glfwInputKey(window, key, [event keyCode], action, mods);
}

- (void)keyUp:(NSEvent *)event
{
    const int key = translateKey([event keyCode]);
    const int mods = translateFlags([event modifierFlags]);
    _glfwInputKey(window, key, [event keyCode], GLFW_RELEASE, mods);
}

- (void)scrollWheel:(NSEvent *)event
{
    double deltaX = [event scrollingDeltaX];
    double deltaY = [event scrollingDeltaY];

    if ([event hasPreciseScrollingDeltas])
    {
        deltaX *= 0.1;
        deltaY *= 0.1;
    }

    if (fabs(deltaX) > 0.0 || fabs(deltaY) > 0.0)
        _glfwInputScroll(window, deltaX, deltaY);
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    // HACK: We don't know what to say here because we don't know what the
    //       application wants to do with the paths
    return NSDragOperationGeneric;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    const NSRect contentRect = [window->ns.view frame];
    // NOTE: The returned location uses base 0,1 not 0,0
    const NSPoint pos = [sender draggingLocation];
    _glfwInputCursorPos(window, pos.x, contentRect.size.height - pos.y);

    NSPasteboard* pasteboard = [sender draggingPasteboard];
    NSDictionary* options = @{NSPasteboardURLReadingFileURLsOnlyKey:@YES};
    NSArray* urls = [pasteboard readObjectsForClasses:@[[NSURL class]]
                                              options:options];
    const NSUInteger count = [urls count];
    if (count)
    {
        char** paths = _glfw_calloc(count, sizeof(char*));

        for (NSUInteger i = 0;  i < count;  i++)
            paths[i] = _glfw_strdup([urls[i] fileSystemRepresentation]);

        _glfwInputDrop(window, (int) count, (const char**) paths);

        for (NSUInteger i = 0;  i < count;  i++)
            _glfw_free(paths[i]);
        _glfw_free(paths);
    }

    return YES;
}

- (BOOL)hasMarkedText
{
    return [markedText length] > 0;
}

- (NSRange)markedRange
{
    if ([markedText length] > 0)
        return NSMakeRange(0, [markedText length] - 1);
    else
        return kEmptyRange;
}

- (NSRange)selectedRange
{
    return kEmptyRange;
}

- (void)setMarkedText:(id)string
        selectedRange:(NSRange)selectedRange
     replacementRange:(NSRange)replacementRange
{
    [markedText release];
    if ([string isKindOfClass:[NSAttributedString class]])
        markedText = [[NSMutableAttributedString alloc] initWithAttributedString:string];
    else
        markedText = [[NSMutableAttributedString alloc] initWithString:string];
}

- (void)unmarkText
{
    [[markedText mutableString] setString:@""];
}

- (NSArray*)validAttributesForMarkedText
{
    return [NSArray array];
}

- (NSAttributedString*)attributedSubstringForProposedRange:(NSRange)range
                                               actualRange:(NSRangePointer)actualRange
{
    return nil;
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point
{
    return 0;
}

- (NSRect)firstRectForCharacterRange:(NSRange)range
                         actualRange:(NSRangePointer)actualRange
{
    const NSRect frame = [window->ns.view frame];
    return NSMakeRect(frame.origin.x, frame.origin.y, 0.0, 0.0);
}

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange
{
    NSString* characters;
    NSEvent* event = [NSApp currentEvent];
    const int mods = translateFlags([event modifierFlags]);
    const int plain = !(mods & GLFW_MOD_SUPER);

    if ([string isKindOfClass:[NSAttributedString class]])
        characters = [string string];
    else
        characters = (NSString*) string;

    NSRange range = NSMakeRange(0, [characters length]);
    while (range.length)
    {
        uint32_t codepoint = 0;

        if ([characters getBytes:&codepoint
                       maxLength:sizeof(codepoint)
                      usedLength:NULL
                        encoding:NSUTF32StringEncoding
                         options:0
                           range:range
                  remainingRange:&range])
        {
            if (codepoint >= 0xf700 && codepoint <= 0xf7ff)
                continue;

            _glfwInputChar(window, codepoint, mods, plain);
        }
    }
}

- (void)doCommandBySelector:(SEL)selector
{
}

@end

//------------------------------------------------------------------------
// GLFW window class
//------------------------------------------------------------------------

@interface GLFWWindow : NSWindow {}
@end

@implementation GLFWWindow

- (BOOL)canBecomeKeyWindow
{
    // Required for NSWindowStyleMaskBorderless windows
    return YES;
}

- (BOOL)canBecomeMainWindow
{
    return YES;
}

@end

// Create the Cocoa window
//
static GLFWbool createNativeWindow(_GLFWwindow* window,
                                   const _GLFWwndconfig* wndconfig,
                                   const _GLFWfbconfig* fbconfig)
{
    window->ns.delegate = [[GLFWWindowDelegate alloc] initWithGlfwWindow:window];
    if (window->ns.delegate == nil)
    {
        _glfwInputError(GLFW_PLATFORM_ERROR,
                        "Cocoa: Failed to create window delegate");
        return GLFW_FALSE;
    }

    NSRect contentRect;

    if (window->monitor)
    {
        GLFWvidmode mode;
        int xpos, ypos;

        _glfwGetVideoModeCocoa(window->monitor, &mode);
        _glfwGetMonitorPosCocoa(window->monitor, &xpos, &ypos);

        contentRect = NSMakeRect(xpos, ypos, mode.width, mode.height);
    }
    else
        contentRect = NSMakeRect(0, 0, wndconfig->width, wndconfig->height);

    window->ns.object = [[GLFWWindow alloc]
        initWithContentRect:contentRect
                  styleMask:getStyleMask(window)
                    backing:NSBackingStoreBuffered
                      defer:NO];

    if (window->ns.object == nil)
    {
        _glfwInputError(GLFW_PLATFORM_ERROR, "Cocoa: Failed to create window");
        return GLFW_FALSE;
    }

    if (window->monitor)
        [window->ns.object setLevel:NSMainMenuWindowLevel + 1];
    else
    {
        [(NSWindow*) window->ns.object center];
        _glfw.ns.cascadePoint =
            NSPointToCGPoint([window->ns.object cascadeTopLeftFromPoint:
                              NSPointFromCGPoint(_glfw.ns.cascadePoint)]);

        if (wndconfig->resizable)
        {
            const NSWindowCollectionBehavior behavior =
                NSWindowCollectionBehaviorFullScreenPrimary |
                NSWindowCollectionBehaviorManaged;
            [window->ns.object setCollectionBehavior:behavior];
        }

        if (wndconfig->floating)
            [window->ns.object setLevel:NSFloatingWindowLevel];

        if (wndconfig->maximized)
            [window->ns.object zoom:nil];
    }

    if (strlen(wndconfig->ns.frameName))
        [window->ns.object setFrameAutosaveName:@(wndconfig->ns.frameName)];

    window->ns.view = [[GLFWContentView alloc] initWithGlfwWindow:window];
    window->ns.retina = wndconfig->ns.retina;

    if (fbconfig->transparent)
    {
        [window->ns.object setOpaque:NO];
        [window->ns.object setHasShadow:NO];
        [window->ns.object setBackgroundColor:[NSColor clearColor]];
    }

    [window->ns.object setContentView:window->ns.view];
    [window->ns.object makeFirstResponder:window->ns.view];
    [window->ns.object setTitle:@(wndconfig->title)];
    [window->ns.object setDelegate:window->ns.delegate];
    [window->ns.object setAcceptsMouseMovedEvents:YES];
    [window->ns.object setRestorable:NO];

#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101200
    if ([window->ns.object respondsToSelector:@selector(setTabbingMode:)])
        [window->ns.object setTabbingMode:NSWindowTabbingModeDisallowed];
#endif

    _glfwGetWindowSizeCocoa(window, &window->ns.width, &window->ns.height);
    _glfwGetFramebufferSizeCocoa(window, &window->ns.fbWidth, &window->ns.fbHeight);

    return GLFW_TRUE;
}

//////////////////////////////////////////////////////////////////////////
//////                       GLFW internal API                      //////
//////////////////////////////////////////////////////////////////////////

// Transforms a y-coordinate between the CG display and NS screen spaces
//
float _glfwTransformYCocoa(float y)
{
    return CGDisplayBounds(CGMainDisplayID()).size.height - y - 1;
}
#endif // NEW_APPLE

#if !NEW_APPLE
//------------------------------------------------------------------------
// GLFW window class
//------------------------------------------------------------------------

@interface GLFWWindow : NSWindow {}
/* These are needed for borderless/fullscreen windows */
- (BOOL)canBecomeKeyWindow;
- (BOOL)canBecomeMainWindow;
- (void)sendEvent:(NSEvent *)event;
@end

@implementation GLFWWindow
- (BOOL)canBecomeKeyWindow
{
    return YES;
}

- (BOOL)canBecomeMainWindow
{
    return YES;
}

- (void)sendEvent:(NSEvent *)event
{
  [super sendEvent:event];

  if ([event type] != NSLeftMouseUp) {
      return;
  }

//   id delegate = [self delegate];
//   if (![delegate isKindOfClass:[Cocoa_WindowListener class]]) {
//       return;
//   }

//   if ([delegate isMoving]) {
//       [delegate windowDidFinishMoving];
//   }
}
@end

@interface GLFWOpenGLContext : NSOpenGLContext {
//    SDL_atomic_t dirty;
//    SDL_Window *window;
}

- (id)initWithFormat:(NSOpenGLPixelFormat *)format
        shareContext:(NSOpenGLContext *)share;
- (void)scheduleUpdate;
- (void)updateIfNeeded;
//- (void)setWindow:(SDL_Window *)window;

@end

@implementation GLFWOpenGLContext : NSOpenGLContext

- (id)initWithFormat:(NSOpenGLPixelFormat *)format
        shareContext:(NSOpenGLContext *)share
{
    self = [super initWithFormat:format shareContext:share];
    // if (self) {
    //     SDL_AtomicSet(&self->dirty, 0);
    //     self->window = NULL;
    // }
    return self;
}

- (void)scheduleUpdate
{
    // SDL_AtomicAdd(&self->dirty, 1);
}

/* This should only be called on the thread on which a user is using the context. */
- (void)updateIfNeeded
{
    // int value = SDL_AtomicSet(&self->dirty, 0);
    // if (value > 0) {
        /* We call the real underlying update here, since -[SDLOpenGLContext update] just calls us. */
        [super update];
    // }
}

/* This should only be called on the thread on which a user is using the context. */
- (void)update
{
    /* This ensures that regular 'update' calls clear the atomic dirty flag. */
    [self scheduleUpdate];
    [self updateIfNeeded];
}

/* Updates the drawable for the contexts and manages related state. */
// - (void)setWindow:(SDL_Window *)newWindow
// {
//     if (self->window) {
//         SDL_WindowData *oldwindowdata = (SDL_WindowData *)self->window->driverdata;

//         /* Make sure to remove us from the old window's context list, or we'll get scheduled updates from it too. */
//         NSMutableArray *contexts = oldwindowdata->nscontexts;
//         @synchronized (contexts) {
//             [contexts removeObject:self];
//         }
//     }

//     self->window = newWindow;

//     if (newWindow) {
//         SDL_WindowData *windowdata = (SDL_WindowData *)newWindow->driverdata;

//         /* Now sign up for scheduled updates for the new window. */
//         NSMutableArray *contexts = windowdata->nscontexts;
//         @synchronized (contexts) {
//             [contexts addObject:self];
//         }

//         if ([self view] != [windowdata->nswindow contentView]) {
//             [self setView:[windowdata->nswindow contentView]];
//             if (self == [NSOpenGLContext currentContext]) {
//                 [self update];
//             } else {
//                 [self scheduleUpdate];
//             }
//         }
//     } else {
//         [self clearDrawable];
//         if (self == [NSOpenGLContext currentContext]) {
//             [self update];
//         } else {
//             [self scheduleUpdate];
//         }
//     }
// }

@end

//@interface GLFWView : NSOpenGLView
@interface GLFWView : NSOpenGLView

/* The default implementation doesn't pass rightMouseDown to responder chain */
- (void)rightMouseDown:(NSEvent *)theEvent;
@end

@implementation GLFWView
- (void)rightMouseDown:(NSEvent *)theEvent
{
    [[self nextResponder] rightMouseDown:theEvent];
}

- (void)resetCursorRects
{
    [super resetCursorRects];
    // SDL_Mouse *mouse = SDL_GetMouse();

    // if (mouse->cursor_shown && mouse->cur_cursor && !mouse->relative_mode) {
    //     [self addCursorRect:[self bounds]
    //                  cursor:mouse->cur_cursor->driverdata];
    // } else {
    //     [self addCursorRect:[self bounds]
    //                  cursor:[NSCursor invisibleCursor]];
    // }
}
@end

// struct _GLFWwndconfig
// {
//     int           width;
//     int           height;
//     const char*   title;
//     GLFWbool      resizable;
//     GLFWbool      visible;
//     GLFWbool      decorated;
//     GLFWbool      focused;
//     GLFWbool      autoIconify;
//     GLFWbool      floating;
//     GLFWbool      maximized;
//     GLFWbool      centerCursor;
//     GLFWbool      focusOnShow;
//     GLFWbool      mousePassthrough;
//     GLFWbool      scaleToMonitor;
//     struct {
//         GLFWbool  retina;
//         char      frameName[256];
//     } ns;
//     struct {
//         char      className[256];
//         char      instanceName[256];
//     } x11;
//     struct {
//         GLFWbool  keymenu;
//     } win32;
// };

static unsigned int GetWindowStyle(GLFWbool fullscreen, GLFWbool borderless, GLFWbool resizable)
{
    unsigned int style = 0;

    if (fullscreen) {
        style = NSBorderlessWindowMask;
    } else {
        if (borderless) {
            style = NSBorderlessWindowMask;
        } else {
            style = (NSTitledWindowMask|NSClosableWindowMask|NSMiniaturizableWindowMask);
        }
        if (resizable) {
            style |= NSResizableWindowMask;
        }
    }

    // Nice good old brushed metal look
    style |= NSTexturedBackgroundWindowMask;

    return style;
}

static int MakeCurrentGLContext(GLFWOpenGLContext* context)
{
    KFX_DBG("Make current context: %p", context);

    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    if (context) {
        //[nscontext setWindow:window];
        [context updateIfNeeded];
        [context makeCurrentContext];
    } else {
        [NSOpenGLContext clearCurrentContext];
    }

    [pool release];
    return 0;
}

static void makeContextCurrentNSGL(_GLFWwindow* window)
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    if (window)
        [window->context.nsgl.object makeCurrentContext];
    else
        [NSOpenGLContext clearCurrentContext];

    _glfwPlatformSetTls(&_glfw.contextSlot, window);

    [pool release];
}

static GLFWglproc getProcAddressNSGL(const char* procname)
{
    CFStringRef symbolName = CFStringCreateWithCString(kCFAllocatorDefault,
                                                       procname,
                                                       kCFStringEncodingASCII);

    //_glfw.nsgl.framework =
//        CFBundleGetBundleWithIdentifier(CFSTR("com.apple.opengl"))

    GLFWglproc symbol = CFBundleGetFunctionPointerForName(CFBundleGetBundleWithIdentifier(CFSTR("com.apple.opengl")),
                                                          symbolName);

    CFRelease(symbolName);

    return symbol;
}

static void swapBuffersNSGL(_GLFWwindow* window)
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    // HACK: Simulate vsync with usleep as NSGL swap interval does not apply to
    //       windows with a non-visible occlusion state
    // if (window->ns.occluded)
    // {
    //     int interval = 0;
    //     [window->context.nsgl.object getValues:&interval
    //                               forParameter:NSOpenGLContextParameterSwapInterval];

    //     if (interval > 0)
    //     {
    //         const double framerate = 60.0;
    //         const uint64_t frequency = _glfwPlatformGetTimerFrequency();
    //         const uint64_t value = _glfwPlatformGetTimerValue();

    //         const double elapsed = value / (double) frequency;
    //         const double period = 1.0 / framerate;
    //         const double delay = period - fmod(elapsed, period);

    //         usleep(floorl(delay * 1e6));
    //     }
    // }

    KFX_DBG("flush buffer");
    [window->context.nsgl.object flushBuffer];

    [pool release];
}

static void swapIntervalNSGL(int interval)
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    _GLFWwindow* window = _glfwPlatformGetTls(&_glfw.contextSlot);
    if (window)
    {
        [window->context.nsgl.object setValues:&interval
                                  forParameter:NSOpenGLCPSwapInterval];
    }

    [pool release];
}

static int extensionSupportedNSGL(const char* extension)
{
    // There are no NSGL extensions
    return GLFW_FALSE;
}

static GLFWOpenGLContext* CreateGLContext(CGDirectDisplayID display,
                                _GLFWwindow* window,
                                const _GLFWctxconfig* ctxconfig,
                                const _GLFWfbconfig* fbconfig)
{
    KFX_DBG("Many missing coeffs");
    // SDL_VideoData *data = (SDL_VideoData *) _this->driverdata;
    // SDL_VideoDisplay *display = SDL_GetDisplayForWindow(window);
    // SDL_DisplayData *displaydata = (SDL_DisplayData *)display->driverdata;
    NSOpenGLPixelFormatAttribute attr[32];
    NSOpenGLPixelFormat *fmt = NULL;
    const char *glversion = NULL;
    int glversion_major;
    int glversion_minor;

    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    //attr[i++] = NSOpenGLPFAColorSize;
    //attr[i++] = SDL_BYTESPERPIXEL(display->current_mode.format)*8;

    //attr[i++] = NSOpenGLPFADepthSize;
    // attr[i++] = _this->gl_config.depth_size;

    // if (_this->gl_config.double_buffer) {
    //     attr[i++] = NSOpenGLPFADoubleBuffer;
    // }

    // if (_this->gl_config.stereo) {
    //     attr[i++] = NSOpenGLPFAStereo;
    // }

    // if (_this->gl_config.stencil_size) {
    //     attr[i++] = NSOpenGLPFAStencilSize;
    //     attr[i++] = _this->gl_config.stencil_size;
    // }

    // if ((_this->gl_config.accum_red_size +
    //      _this->gl_config.accum_green_size +
    //      _this->gl_config.accum_blue_size +
    //      _this->gl_config.accum_alpha_size) > 0) {
    //     attr[i++] = NSOpenGLPFAAccumSize;
    //     attr[i++] = _this->gl_config.accum_red_size + _this->gl_config.accum_green_size + _this->gl_config.accum_blue_size + _this->gl_config.accum_alpha_size;
    // }

    // if (_this->gl_config.multisamplebuffers) {
    //     attr[i++] = NSOpenGLPFASampleBuffers;
    //     attr[i++] = _this->gl_config.multisamplebuffers;
    // }

    // if (_this->gl_config.multisamplesamples) {
    //     attr[i++] = NSOpenGLPFASamples;
    //     attr[i++] = _this->gl_config.multisamplesamples;
    //     attr[i++] = NSOpenGLPFANoRecovery;
    // }

    // if (_this->gl_config.accelerated >= 0) {
    //     if (_this->gl_config.accelerated) {
    //         attr[i++] = NSOpenGLPFAAccelerated;
    //     } else {
    //         attr[i++] = NSOpenGLPFARendererID;
    //         attr[i++] = kCGLRendererGenericFloatID;
    //     }
    // }

#define ADD_ATTRIB(a) \
{ \
    assert((size_t) index < sizeof(attribs) / sizeof(attr[0])); \
    attr[index++] = a; \
}
#define SET_ATTRIB(a, v) { ADD_ATTRIB(a); ADD_ATTRIB(v); }

    NSOpenGLPixelFormatAttribute attribs[40];
    int index = 0;

    ADD_ATTRIB(NSOpenGLPFAAccelerated);
    ADD_ATTRIB(NSOpenGLPFAClosestPolicy);

    if (ctxconfig->major <= 2)
    {
        if (fbconfig->auxBuffers != GLFW_DONT_CARE)
            SET_ATTRIB(NSOpenGLPFAAuxBuffers, fbconfig->auxBuffers);

        if (fbconfig->accumRedBits != GLFW_DONT_CARE &&
            fbconfig->accumGreenBits != GLFW_DONT_CARE &&
            fbconfig->accumBlueBits != GLFW_DONT_CARE &&
            fbconfig->accumAlphaBits != GLFW_DONT_CARE)
        {
            const int accumBits = fbconfig->accumRedBits +
                                  fbconfig->accumGreenBits +
                                  fbconfig->accumBlueBits +
                                  fbconfig->accumAlphaBits;

            SET_ATTRIB(NSOpenGLPFAAccumSize, accumBits);
        }
    }

    if (fbconfig->redBits != GLFW_DONT_CARE &&
        fbconfig->greenBits != GLFW_DONT_CARE &&
        fbconfig->blueBits != GLFW_DONT_CARE)
    {
        int colorBits = fbconfig->redBits +
                        fbconfig->greenBits +
                        fbconfig->blueBits;

        // macOS needs non-zero color size, so set reasonable values
        if (colorBits == 0)
            colorBits = 24;
        else if (colorBits < 15)
            colorBits = 15;

        SET_ATTRIB(NSOpenGLPFAColorSize, colorBits);
    }

    if (fbconfig->alphaBits != GLFW_DONT_CARE)
        SET_ATTRIB(NSOpenGLPFAAlphaSize, fbconfig->alphaBits);

    if (fbconfig->depthBits != GLFW_DONT_CARE)
        SET_ATTRIB(NSOpenGLPFADepthSize, fbconfig->depthBits);

    if (fbconfig->stencilBits != GLFW_DONT_CARE)
        SET_ATTRIB(NSOpenGLPFAStencilSize, fbconfig->stencilBits);

    if (fbconfig->stereo)
    {
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101200
        _glfwInputError(GLFW_FORMAT_UNAVAILABLE,
                        "NSGL: Stereo rendering is deprecated");
        return GLFW_FALSE;
#else
        ADD_ATTRIB(NSOpenGLPFAStereo);
#endif
    }

    if (fbconfig->doublebuffer)
        ADD_ATTRIB(NSOpenGLPFADoubleBuffer);

    if (fbconfig->samples != GLFW_DONT_CARE)
    {
        if (fbconfig->samples == 0)
        {
            SET_ATTRIB(NSOpenGLPFASampleBuffers, 0);
        }
        else
        {
            SET_ATTRIB(NSOpenGLPFASampleBuffers, 1);
            SET_ATTRIB(NSOpenGLPFASamples, fbconfig->samples);
        }
    }











    SET_ATTRIB(NSOpenGLPFAScreenMask, CGDisplayIDToOpenGLDisplayMask(display));
    ADD_ATTRIB(0);

    fmt = [[NSOpenGLPixelFormat alloc] initWithAttributes:attr];
    if (fmt == nil) {
        _glfwInputError(GLFW_FORMAT_UNAVAILABLE, "Failed creating OpenGL pixel format");
        [pool release];
        return NULL;
    }

    NSOpenGLContext* shareContext = nil;
    // if (_this->gl_config.share_with_current_context) {
    //     share_context = (NSOpenGLContext*)SDL_GL_GetCurrentContext();
    // }

    GLFWOpenGLContext* context = [[GLFWOpenGLContext alloc] initWithFormat:fmt shareContext:shareContext];

    [fmt release];

    if (context == nil) {
        _glfwInputError(GLFW_PLATFORM_ERROR, "Failed creating OpenGL context");
        [pool release];
        return NULL;
    }

    [pool release];

    // KFX TODO: Isn't this supposed to happen later?
    if (MakeCurrentGLContext(context) < 0 ) {
        [context release];
        _glfwInputError(GLFW_PLATFORM_ERROR, "Failed making OpenGL context current");
        return NULL;
    }

    // if (_this->gl_config.major_version < 3 &&
    //     _this->gl_config.profile_mask == 0 &&
    //     _this->gl_config.flags == 0) {
    //     /* This is a legacy profile, so to match other backends, we're done. */
    // } else {
    //     const GLubyte *(APIENTRY * glGetStringFunc)(GLenum);

    //     glGetStringFunc = (const GLubyte *(APIENTRY *)(GLenum)) SDL_GL_GetProcAddress("glGetString");
    //     if (!glGetStringFunc) {
    //         Cocoa_GL_DeleteContext(_this, context);
    //         _glfwInputError(GLFW_PLATFORM_ERROR, "Failed getting OpenGL glGetString entry point");
    //         return NULL;
    //     }

    //     glversion = (const char *)glGetStringFunc(GL_VERSION);
    //     if (glversion == NULL) {
    //         Cocoa_GL_DeleteContext(_this, context);
    //         _glfwInputError(GLFW_PLATFORM_ERROR, "Failed getting OpenGL context version");
    //         return NULL;
    //     }

    //     if (SDL_sscanf(glversion, "%d.%d", &glversion_major, &glversion_minor) != 2) {
    //         Cocoa_GL_DeleteContext(_this, context);
    //         _glfwInputError(GLFW_PLATFORM_ERROR, "Failed parsing OpenGL context version");
    //         return NULL;
    //     }

    //     if ((glversion_major < _this->gl_config.major_version) ||
    //        ((glversion_major == _this->gl_config.major_version) && (glversion_minor < _this->gl_config.minor_version))) {
    //         Cocoa_GL_DeleteContext(_this, context);
    //         _glfwInputError(GLFW_PLATFORM_ERROR, "Failed creating OpenGL context at version requested");
    //         return NULL;
    //     }

    //     /* In the future we'll want to do this, but to match other platforms
    //        we'll leave the OpenGL version the way it is for now
    //      */
    //     /*_this->gl_config.major_version = glversion_major;*/
    //     /*_this->gl_config.minor_version = glversion_minor;*/
    // }

    window->context.makeCurrent = makeContextCurrentNSGL;
    window->context.swapBuffers = swapBuffersNSGL;
    window->context.swapInterval = swapIntervalNSGL;
    window->context.extensionSupported = extensionSupportedNSGL;
    window->context.getProcAddress = getProcAddressNSGL;
    // window->context.destroy = destroyContextNSGL;

    return context;
}
#endif

//////////////////////////////////////////////////////////////////////////
//////                       GLFW platform API                      //////
//////////////////////////////////////////////////////////////////////////
#if NEW_APPLE
GLFWbool _glfwCreateWindowCocoa(_GLFWwindow* window,
                                const _GLFWwndconfig* wndconfig,
                                const _GLFWctxconfig* ctxconfig,
                                const _GLFWfbconfig* fbconfig)
{
    @autoreleasepool {

    if (!createNativeWindow(window, wndconfig, fbconfig))
        return GLFW_FALSE;

    if (ctxconfig->client != GLFW_NO_API)
    {
        if (ctxconfig->source == GLFW_NATIVE_CONTEXT_API)
        {
            if (!_glfwInitNSGL())
                return GLFW_FALSE;
            if (!_glfwCreateContextNSGL(window, ctxconfig, fbconfig))
                return GLFW_FALSE;
        }
        else if (ctxconfig->source == GLFW_EGL_CONTEXT_API)
        {
            // EGL implementation on macOS use CALayer* EGLNativeWindowType so we
            // need to get the layer for EGL window surface creation.
            [window->ns.view setWantsLayer:YES];
            window->ns.layer = [window->ns.view layer];

            if (!_glfwInitEGL())
                return GLFW_FALSE;
            if (!_glfwCreateContextEGL(window, ctxconfig, fbconfig))
                return GLFW_FALSE;
        }
        else if (ctxconfig->source == GLFW_OSMESA_CONTEXT_API)
        {
            if (!_glfwInitOSMesa())
                return GLFW_FALSE;
            if (!_glfwCreateContextOSMesa(window, ctxconfig, fbconfig))
                return GLFW_FALSE;
        }

        if (!_glfwRefreshContextAttribs(window, ctxconfig))
            return GLFW_FALSE;
    }

    if (wndconfig->mousePassthrough)
        _glfwSetWindowMousePassthroughCocoa(window, GLFW_TRUE);

    if (window->monitor)
    {
        _glfwShowWindowCocoa(window);
        _glfwFocusWindowCocoa(window);
        acquireMonitor(window);

        if (wndconfig->centerCursor)
            _glfwCenterCursorInContentArea(window);
    }
    else
    {
        if (wndconfig->visible)
        {
            _glfwShowWindowCocoa(window);
            if (wndconfig->focused)
                _glfwFocusWindowCocoa(window);
        }
    }

    return GLFW_TRUE;

    } // autoreleasepool
}
#else // NEW_APPLE
GLFWbool _glfwCreateWindowCocoa(_GLFWwindow* window,
                                const _GLFWwndconfig* wndconfig,
                                const _GLFWctxconfig* ctxconfig,
                                const _GLFWfbconfig* fbconfig)
{
    KFX_DBG("NOT IMPLEMENTED");

    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    KFX_DBG("TODO: Opening window on [0, 0], use automatic placement");
    NSRect rect = {};
    rect.origin.x = 0;
    rect.origin.y = 0;
    rect.size.width = wndconfig->width;
    rect.size.height = wndconfig->height;

    KFX_DBG("TODO: convert NSRect to native space via CGDisplayPixelsHigh(kCGDirectMainDisplay)");

    NSArray* screens = [NSScreen screens];
    KFX_DBG("Screens count: %i", [screens count]);
    KFX_DBG("TODO: select proper screen");
    NSScreen* screen = [screens objectAtIndex: 0];

    unsigned int style = GetWindowStyle(GLFW_FALSE, GLFW_FALSE, wndconfig->resizable);
    KFX_DBG("initWithContentRect:[%lf, %lf, %lf, %lf] styleMask:%u screen:%p",
        rect.origin.x,
        rect.origin.y,
        rect.size.width,
        rect.size.height,
        style,
        screen);

    NSWindow* nswindow = [[GLFWWindow alloc] initWithContentRect:rect styleMask:style backing:NSBackingStoreBuffered defer:NO screen:screen];
    window->ns.nswindow = nswindow;

    /* Create a default view for this window */
    rect = [nswindow contentRectForFrameRect:[nswindow frame]];
    KFX_DBG("contentRectForFrameRect: [%lf, %lf, %lf, %lf]",
    rect.origin.x,
    rect.origin.y,
    rect.size.width,
    rect.size.height);

    NSView* contentView = [[GLFWView alloc] initWithFrame:rect];

    // if (window->flags & SDL_WINDOW_ALLOW_HIGHDPI) {
    //     if ([contentView respondsToSelector:@selector(setWantsBestResolutionOpenGLSurface:)]) {
    //         [contentView setWantsBestResolutionOpenGLSurface:YES];
    //     }
    // }

    KFX_DBG("setContentView: ");
    [nswindow setContentView: contentView];
    /* Prevents the window's "window device" from being destroyed when it is
     * hidden. See http://www.mikeash.com/pyblog/nsopenglcontext-and-one-shot.html
     */
     KFX_DBG("setOneShot");
    [nswindow setOneShot:NO];


    KFX_DBG("orderFront");
    [nswindow orderFront: nil];
    // Show window
    KFX_DBG("makeKeyAndOrderFront");
    [nswindow makeKeyAndOrderFront:nil];

    KFX_DBG("makeFirstResponder");
    [nswindow makeFirstResponder:contentView];
    //[nswindow setTitle:wndconfig->title];
    //[nswindow setDelegate:window->ns.delegate];

    KFX_DBG("setDelegate: NSResponder alloc");
    [nswindow setDelegate: [[NSResponder alloc] init]];

    KFX_DBG("setAcceptsMouseMovedEvents");
    [nswindow setAcceptsMouseMovedEvents:YES];

    // Not on tiger (at min)
    // [nswindow setRestorable:NO];




    if (ctxconfig->client != GLFW_NO_API)
    {
        if (ctxconfig->source == GLFW_NATIVE_CONTEXT_API)
        {
                uint32_t displayCount = 0;
                CGGetOnlineDisplayList(0, NULL, &displayCount);
                KFX_DBG("CGGetOnlineDisplayList count: %i", displayCount);
                CGDirectDisplayID* displays = _glfw_calloc(displayCount, sizeof(CGDirectDisplayID));
                CGGetOnlineDisplayList(displayCount, displays, &displayCount);

                KFX_DBG("TODO: Taking the first display, use CGDisplayIsMain(displays[i]), skip CGDisplayMirrorsDisplay");
                GLFWOpenGLContext* context = CreateGLContext(displays[0], window, ctxconfig, fbconfig);
                window->context.nsgl.object = context;
                [context setView: contentView];

                KFX_DBG("context: %p", context);

                KFX_DBG("_glfwPlatformSetTls: %p", window);
                _glfwPlatformSetTls(&_glfw.contextSlot, window);

                _glfw_free(displays);
        }
        else if (ctxconfig->source == GLFW_OSMESA_CONTEXT_API)
        {
            if (!_glfwInitOSMesa())
                return GLFW_FALSE;
            if (!_glfwCreateContextOSMesa(window, ctxconfig, fbconfig))
                return GLFW_FALSE;
        }
        else if (ctxconfig->source == GLFW_EGL_CONTEXT_API)
        {
            _glfwInputError(GLFW_PLATFORM_ERROR, "EGL context unsupported on this platform.");
        }

        if (!_glfwRefreshContextAttribs(window, ctxconfig))
            return GLFW_FALSE;
    }







    [contentView release];
    [pool release];

    return GLFW_TRUE;
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwDestroyWindowCocoa(_GLFWwindow* window)
{
    @autoreleasepool {

    if (_glfw.ns.disabledCursorWindow == window)
        _glfw.ns.disabledCursorWindow = NULL;

    [window->ns.object orderOut:nil];

    if (window->monitor)
        releaseMonitor(window);

    if (window->context.destroy)
        window->context.destroy(window);

    [window->ns.object setDelegate:nil];
    [window->ns.delegate release];
    window->ns.delegate = nil;

    [window->ns.view release];
    window->ns.view = nil;

    [window->ns.object close];
    window->ns.object = nil;

    // HACK: Allow Cocoa to catch up before returning
    _glfwPollEventsCocoa();

    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwDestroyWindowCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");

    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    [pool release];
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwSetWindowTitleCocoa(_GLFWwindow* window, const char* title)
{
    @autoreleasepool {
    NSString* string = @(title);
    [window->ns.object setTitle:string];
    // HACK: Set the miniwindow title explicitly as setTitle: doesn't update it
    //       if the window lacks NSWindowStyleMaskTitled
    [window->ns.object setMiniwindowTitle:string];
    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwSetWindowTitleCocoa(_GLFWwindow* window, const char* title)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

void _glfwSetWindowIconCocoa(_GLFWwindow* window,
                             int count, const GLFWimage* images)
{
    _glfwInputError(GLFW_FEATURE_UNAVAILABLE,
                    "Cocoa: Regular windows do not have icons on macOS");
}

#if NEW_APPLE
void _glfwGetWindowPosCocoa(_GLFWwindow* window, int* xpos, int* ypos)
{
    @autoreleasepool {

    const NSRect contentRect =
        [window->ns.object contentRectForFrameRect:[window->ns.object frame]];

    if (xpos)
        *xpos = contentRect.origin.x;
    if (ypos)
        *ypos = _glfwTransformYCocoa(contentRect.origin.y + contentRect.size.height - 1);

    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwGetWindowPosCocoa(_GLFWwindow* window, int* xpos, int* ypos)
{
    KFX_DBG("NOT IMPLEMENTED - returning [0, 0]");
    if (xpos)
        *xpos = 0;
    if (ypos)
        *ypos = 0;
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwSetWindowPosCocoa(_GLFWwindow* window, int x, int y)
{
    @autoreleasepool {

    const NSRect contentRect = [window->ns.view frame];
    const NSRect dummyRect = NSMakeRect(x, _glfwTransformYCocoa(y + contentRect.size.height - 1), 0, 0);
    const NSRect frameRect = [window->ns.object frameRectForContentRect:dummyRect];
    [window->ns.object setFrameOrigin:frameRect.origin];

    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwSetWindowPosCocoa(_GLFWwindow* window, int x, int y)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwGetWindowSizeCocoa(_GLFWwindow* window, int* width, int* height)
{
    @autoreleasepool {

    const NSRect contentRect = [window->ns.view frame];

    if (width)
        *width = contentRect.size.width;
    if (height)
        *height = contentRect.size.height;

    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwGetWindowSizeCocoa(_GLFWwindow* window, int* width, int* height)
{
    KFX_DBG("NOT IMPLEMENTED - returning [800, 600]");
    if (width)
        *width = 800;
    if (height)
        *height = 600;
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwSetWindowSizeCocoa(_GLFWwindow* window, int width, int height)
{
    @autoreleasepool {

    if (window->monitor)
    {
        if (window->monitor->window == window)
            acquireMonitor(window);
    }
    else
    {
        NSRect contentRect =
            [window->ns.object contentRectForFrameRect:[window->ns.object frame]];
        contentRect.origin.y += contentRect.size.height - height;
        contentRect.size = NSMakeSize(width, height);
        [window->ns.object setFrame:[window->ns.object frameRectForContentRect:contentRect]
                            display:YES];
    }

    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwSetWindowSizeCocoa(_GLFWwindow* window, int width, int height)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwSetWindowSizeLimitsCocoa(_GLFWwindow* window,
                                   int minwidth, int minheight,
                                   int maxwidth, int maxheight)
{
    @autoreleasepool {

    if (minwidth == GLFW_DONT_CARE || minheight == GLFW_DONT_CARE)
        [window->ns.object setContentMinSize:NSMakeSize(0, 0)];
    else
        [window->ns.object setContentMinSize:NSMakeSize(minwidth, minheight)];

    if (maxwidth == GLFW_DONT_CARE || maxheight == GLFW_DONT_CARE)
        [window->ns.object setContentMaxSize:NSMakeSize(DBL_MAX, DBL_MAX)];
    else
        [window->ns.object setContentMaxSize:NSMakeSize(maxwidth, maxheight)];

    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwSetWindowSizeLimitsCocoa(_GLFWwindow* window,
                                   int minwidth, int minheight,
                                   int maxwidth, int maxheight)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwSetWindowAspectRatioCocoa(_GLFWwindow* window, int numer, int denom)
{
    @autoreleasepool {
    if (numer == GLFW_DONT_CARE || denom == GLFW_DONT_CARE)
        [window->ns.object setResizeIncrements:NSMakeSize(1.0, 1.0)];
    else
        [window->ns.object setContentAspectRatio:NSMakeSize(numer, denom)];
    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwSetWindowAspectRatioCocoa(_GLFWwindow* window, int numer, int denom)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwGetFramebufferSizeCocoa(_GLFWwindow* window, int* width, int* height)
{
    @autoreleasepool {

    const NSRect contentRect = [window->ns.view frame];
    const NSRect fbRect = [window->ns.view convertRectToBacking:contentRect];

    if (width)
        *width = (int) fbRect.size.width;
    if (height)
        *height = (int) fbRect.size.height;

    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwGetFramebufferSizeCocoa(_GLFWwindow* window, int* width, int* height)
{
    KFX_DBG("NOT IMPLEMENTED - returning [800, 600]");
    if (width)
        *width = 800;
    if (height)
        *height = 600;
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwGetWindowFrameSizeCocoa(_GLFWwindow* window,
                                  int* left, int* top,
                                  int* right, int* bottom)
{
    @autoreleasepool {

    const NSRect contentRect = [window->ns.view frame];
    const NSRect frameRect = [window->ns.object frameRectForContentRect:contentRect];

    if (left)
        *left = contentRect.origin.x - frameRect.origin.x;
    if (top)
        *top = frameRect.origin.y + frameRect.size.height -
               contentRect.origin.y - contentRect.size.height;
    if (right)
        *right = frameRect.origin.x + frameRect.size.width -
                 contentRect.origin.x - contentRect.size.width;
    if (bottom)
        *bottom = contentRect.origin.y - frameRect.origin.y;

    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwGetWindowFrameSizeCocoa(_GLFWwindow* window,
                                  int* left, int* top,
                                  int* right, int* bottom)
{
    KFX_DBG("NOT IMPLEMENTED - returning [0, 0] [800, 600]");
    if (left)
        *left = 0;
    if (top)
        *top = 0;
    if (right)
        *right = 800;
    if (bottom)
        *bottom = 600;
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwGetWindowContentScaleCocoa(_GLFWwindow* window,
                                     float* xscale, float* yscale)
{
    @autoreleasepool {

    const NSRect points = [window->ns.view frame];
    const NSRect pixels = [window->ns.view convertRectToBacking:points];

    if (xscale)
        *xscale = (float) (pixels.size.width / points.size.width);
    if (yscale)
        *yscale = (float) (pixels.size.height / points.size.height);

    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwGetWindowContentScaleCocoa(_GLFWwindow* window,
                                     float* xscale, float* yscale)
{
    KFX_DBG("NOT IMPLEMENTED - returning [1, 1]");
    if (xscale)
        *xscale = 1;
    if (yscale)
        *yscale = 1;
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwIconifyWindowCocoa(_GLFWwindow* window)
{
    @autoreleasepool {
    [window->ns.object miniaturize:nil];
    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwIconifyWindowCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwRestoreWindowCocoa(_GLFWwindow* window)
{
    @autoreleasepool {
    if ([window->ns.object isMiniaturized])
        [window->ns.object deminiaturize:nil];
    else if ([window->ns.object isZoomed])
        [window->ns.object zoom:nil];
    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwRestoreWindowCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwMaximizeWindowCocoa(_GLFWwindow* window)
{
    @autoreleasepool {
    if (![window->ns.object isZoomed])
        [window->ns.object zoom:nil];
    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwMaximizeWindowCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwShowWindowCocoa(_GLFWwindow* window)
{
    @autoreleasepool {
    [window->ns.object orderFront:nil];
    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwShowWindowCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwHideWindowCocoa(_GLFWwindow* window)
{
    @autoreleasepool {
    [window->ns.object orderOut:nil];
    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwHideWindowCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwRequestWindowAttentionCocoa(_GLFWwindow* window)
{
    @autoreleasepool {
    [NSApp requestUserAttention:NSInformationalRequest];
    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwRequestWindowAttentionCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwFocusWindowCocoa(_GLFWwindow* window)
{
    @autoreleasepool {
    // Make us the active application
    // HACK: This is here to prevent applications using only hidden windows from
    //       being activated, but should probably not be done every time any
    //       window is shown
    [NSApp activateIgnoringOtherApps:YES];
    [window->ns.object makeKeyAndOrderFront:nil];
    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwFocusWindowCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwSetWindowMonitorCocoa(_GLFWwindow* window,
                                _GLFWmonitor* monitor,
                                int xpos, int ypos,
                                int width, int height,
                                int refreshRate)
{
    @autoreleasepool {

    if (window->monitor == monitor)
    {
        if (monitor)
        {
            if (monitor->window == window)
                acquireMonitor(window);
        }
        else
        {
            const NSRect contentRect =
                NSMakeRect(xpos, _glfwTransformYCocoa(ypos + height - 1), width, height);
            const NSRect frameRect =
                [window->ns.object frameRectForContentRect:contentRect
                                                 styleMask:getStyleMask(window)];

            [window->ns.object setFrame:frameRect display:YES];
        }

        return;
    }

    if (window->monitor)
        releaseMonitor(window);

    _glfwInputWindowMonitor(window, monitor);

    // HACK: Allow the state cached in Cocoa to catch up to reality
    // TODO: Solve this in a less terrible way
    _glfwPollEventsCocoa();

    const NSUInteger styleMask = getStyleMask(window);
    [window->ns.object setStyleMask:styleMask];
    // HACK: Changing the style mask can cause the first responder to be cleared
    [window->ns.object makeFirstResponder:window->ns.view];

    if (window->monitor)
    {
        [window->ns.object setLevel:NSMainMenuWindowLevel + 1];
        [window->ns.object setHasShadow:NO];

        acquireMonitor(window);
    }
    else
    {
        NSRect contentRect = NSMakeRect(xpos, _glfwTransformYCocoa(ypos + height - 1),
                                        width, height);
        NSRect frameRect = [window->ns.object frameRectForContentRect:contentRect
                                                            styleMask:styleMask];
        [window->ns.object setFrame:frameRect display:YES];

        if (window->numer != GLFW_DONT_CARE &&
            window->denom != GLFW_DONT_CARE)
        {
            [window->ns.object setContentAspectRatio:NSMakeSize(window->numer,
                                                                window->denom)];
        }

        if (window->minwidth != GLFW_DONT_CARE &&
            window->minheight != GLFW_DONT_CARE)
        {
            [window->ns.object setContentMinSize:NSMakeSize(window->minwidth,
                                                            window->minheight)];
        }

        if (window->maxwidth != GLFW_DONT_CARE &&
            window->maxheight != GLFW_DONT_CARE)
        {
            [window->ns.object setContentMaxSize:NSMakeSize(window->maxwidth,
                                                            window->maxheight)];
        }

        if (window->floating)
            [window->ns.object setLevel:NSFloatingWindowLevel];
        else
            [window->ns.object setLevel:NSNormalWindowLevel];

        [window->ns.object setHasShadow:YES];
        // HACK: Clearing NSWindowStyleMaskTitled resets and disables the window
        //       title property but the miniwindow title property is unaffected
        [window->ns.object setTitle:[window->ns.object miniwindowTitle]];
    }

    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwSetWindowMonitorCocoa(_GLFWwindow* window,
                                _GLFWmonitor* monitor,
                                int xpos, int ypos,
                                int width, int height,
                                int refreshRate)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
GLFWbool _glfwWindowFocusedCocoa(_GLFWwindow* window)
{
    @autoreleasepool {
    return [window->ns.object isKeyWindow];
    } // autoreleasepool
}
#else // NEW_APPLE
GLFWbool _glfwWindowFocusedCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
    return GLFW_TRUE;
}
#endif // NEW_APPLE

#if NEW_APPLE
GLFWbool _glfwWindowIconifiedCocoa(_GLFWwindow* window)
{
    @autoreleasepool {
    return [window->ns.object isMiniaturized];
    } // autoreleasepool
}
#else // NEW_APPLE
GLFWbool _glfwWindowIconifiedCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
    return GLFW_TRUE;
}
#endif // NEW_APPLE

#if NEW_APPLE
GLFWbool _glfwWindowVisibleCocoa(_GLFWwindow* window)
{
    @autoreleasepool {
    return [window->ns.object isVisible];
    } // autoreleasepool
}
#else // NEW_APPLE
GLFWbool _glfwWindowVisibleCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
    return GLFW_TRUE;
}
#endif // NEW_APPLE

#if NEW_APPLE
GLFWbool _glfwWindowMaximizedCocoa(_GLFWwindow* window)
{
    @autoreleasepool {
    return [window->ns.object isZoomed];
    } // autoreleasepool
}
#else // NEW_APPLE
GLFWbool _glfwWindowMaximizedCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
    return GLFW_TRUE;
}
#endif // NEW_APPLE

#if NEW_APPLE
GLFWbool _glfwWindowHoveredCocoa(_GLFWwindow* window)
{
    @autoreleasepool {

    const NSPoint point = [NSEvent mouseLocation];

    if ([NSWindow windowNumberAtPoint:point belowWindowWithWindowNumber:0] !=
        [window->ns.object windowNumber])
    {
        return GLFW_FALSE;
    }

    return NSMouseInRect(point,
        [window->ns.object convertRectToScreen:[window->ns.view frame]], NO);

    } // autoreleasepool
}
#else // NEW_APPLE
GLFWbool _glfwWindowHoveredCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
    return GLFW_TRUE;
}
#endif // NEW_APPLE

#if NEW_APPLE
GLFWbool _glfwFramebufferTransparentCocoa(_GLFWwindow* window)
{
    @autoreleasepool {
    return ![window->ns.object isOpaque] && ![window->ns.view isOpaque];
    } // autoreleasepool
}
#else // NEW_APPLE
GLFWbool _glfwFramebufferTransparentCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
    return GLFW_TRUE;
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwSetWindowResizableCocoa(_GLFWwindow* window, GLFWbool enabled)
{
    @autoreleasepool {
    [window->ns.object setStyleMask:getStyleMask(window)];
    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwSetWindowResizableCocoa(_GLFWwindow* window, GLFWbool enabled)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwSetWindowDecoratedCocoa(_GLFWwindow* window, GLFWbool enabled)
{
    @autoreleasepool {
    [window->ns.object setStyleMask:getStyleMask(window)];
    [window->ns.object makeFirstResponder:window->ns.view];
    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwSetWindowDecoratedCocoa(_GLFWwindow* window, GLFWbool enabled)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwSetWindowFloatingCocoa(_GLFWwindow* window, GLFWbool enabled)
{
    @autoreleasepool {
    if (enabled)
        [window->ns.object setLevel:NSFloatingWindowLevel];
    else
        [window->ns.object setLevel:NSNormalWindowLevel];
    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwSetWindowFloatingCocoa(_GLFWwindow* window, GLFWbool enabled)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwSetWindowMousePassthroughCocoa(_GLFWwindow* window, GLFWbool enabled)
{
    @autoreleasepool {
    [window->ns.object setIgnoresMouseEvents:enabled];
    }
}
#else // NEW_APPLE
void _glfwSetWindowMousePassthroughCocoa(_GLFWwindow* window, GLFWbool enabled)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
float _glfwGetWindowOpacityCocoa(_GLFWwindow* window)
{
    @autoreleasepool {
    return (float) [window->ns.object alphaValue];
    } // autoreleasepool
}
#else // NEW_APPLE
float _glfwGetWindowOpacityCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED - returning 1");
    return 1.0f;
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwSetWindowOpacityCocoa(_GLFWwindow* window, float opacity)
{
    @autoreleasepool {
    [window->ns.object setAlphaValue:opacity];
    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwSetWindowOpacityCocoa(_GLFWwindow* window, float opacity)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

void _glfwSetRawMouseMotionCocoa(_GLFWwindow *window, GLFWbool enabled)
{
    _glfwInputError(GLFW_FEATURE_UNIMPLEMENTED,
                    "Cocoa: Raw mouse motion not yet implemented");
}

GLFWbool _glfwRawMouseMotionSupportedCocoa(void)
{
    return GLFW_FALSE;
}

#if NEW_APPLE
void _glfwPollEventsCocoa(void)
{
    @autoreleasepool {

    for (;;)
    {
        NSEvent* event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                            untilDate:[NSDate distantPast]
                                               inMode:NSDefaultRunLoopMode
                                              dequeue:YES];
        if (event == nil)
            break;

        [NSApp sendEvent:event];
    }

    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwPollEventsCocoa(void)
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    // /* Update activity every 30 seconds to prevent screensaver */
    // if (_this->suspend_screensaver) {
    //     SDL_VideoData *data = (SDL_VideoData *)_this->driverdata;
    //     Uint32 now = SDL_GetTicks();
    //     if (!data->screensaver_activity ||
    //         SDL_TICKS_PASSED(now, data->screensaver_activity + 30000)) {
    //         UpdateSystemActivity(UsrActivity);
    //         data->screensaver_activity = now;
    //     }
    // }

    for (;;)
    {
        NSEvent* event = [NSApp nextEventMatchingMask:NSAnyEventMask
                                            untilDate:[NSDate distantPast]
                                               inMode:NSDefaultRunLoopMode
                                              dequeue:YES];
        if (event == nil)
            break;

        [NSApp sendEvent:event];
    }

    [pool release];
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwWaitEventsCocoa(void)
{
    @autoreleasepool {

    // I wanted to pass NO to dequeue:, and rely on PollEvents to
    // dequeue and send.  For reasons not at all clear to me, passing
    // NO to dequeue: causes this method never to return.
    NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                        untilDate:[NSDate distantFuture]
                                           inMode:NSDefaultRunLoopMode
                                          dequeue:YES];
    [NSApp sendEvent:event];

    _glfwPollEventsCocoa();

    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwWaitEventsCocoa(void)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwWaitEventsTimeoutCocoa(double timeout)
{
    @autoreleasepool {

    NSDate* date = [NSDate dateWithTimeIntervalSinceNow:timeout];
    NSEvent* event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                        untilDate:date
                                           inMode:NSDefaultRunLoopMode
                                          dequeue:YES];
    if (event)
        [NSApp sendEvent:event];

    _glfwPollEventsCocoa();

    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwWaitEventsTimeoutCocoa(double timeout)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwPostEmptyEventCocoa(void)
{
    @autoreleasepool {

    NSEvent* event = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                        location:NSMakePoint(0, 0)
                                   modifierFlags:0
                                       timestamp:0
                                    windowNumber:0
                                         context:nil
                                         subtype:0
                                           data1:0
                                           data2:0];
    [NSApp postEvent:event atStart:YES];

    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwPostEmptyEventCocoa(void)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwGetCursorPosCocoa(_GLFWwindow* window, double* xpos, double* ypos)
{
    @autoreleasepool {

    const NSRect contentRect = [window->ns.view frame];
    // NOTE: The returned location uses base 0,1 not 0,0
    const NSPoint pos = [window->ns.object mouseLocationOutsideOfEventStream];

    if (xpos)
        *xpos = pos.x;
    if (ypos)
        *ypos = contentRect.size.height - pos.y;

    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwGetCursorPosCocoa(_GLFWwindow* window, double* xpos, double* ypos)
{
    KFX_DBG("NOT IMPLEMENTED - returning [400, 300]");
    if (xpos)
        *xpos = 400;
    if (ypos)
        *ypos = 300;
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwSetCursorPosCocoa(_GLFWwindow* window, double x, double y)
{
    @autoreleasepool {

    updateCursorImage(window);

    const NSRect contentRect = [window->ns.view frame];
    // NOTE: The returned location uses base 0,1 not 0,0
    const NSPoint pos = [window->ns.object mouseLocationOutsideOfEventStream];

    window->ns.cursorWarpDeltaX += x - pos.x;
    window->ns.cursorWarpDeltaY += y - contentRect.size.height + pos.y;

    if (window->monitor)
    {
        CGDisplayMoveCursorToPoint(window->monitor->ns.displayID,
                                   CGPointMake(x, y));
    }
    else
    {
        const NSRect localRect = NSMakeRect(x, contentRect.size.height - y - 1, 0, 0);
        const NSRect globalRect = [window->ns.object convertRectToScreen:localRect];
        const NSPoint globalPoint = globalRect.origin;

        CGWarpMouseCursorPosition(CGPointMake(globalPoint.x,
                                              _glfwTransformYCocoa(globalPoint.y)));
    }

    // HACK: Calling this right after setting the cursor position prevents macOS
    //       from freezing the cursor for a fraction of a second afterwards
    if (window->cursorMode != GLFW_CURSOR_DISABLED)
        CGAssociateMouseAndMouseCursorPosition(true);

    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwSetCursorPosCocoa(_GLFWwindow* window, double x, double y)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwSetCursorModeCocoa(_GLFWwindow* window, int mode)
{
    @autoreleasepool {
    if (_glfwWindowFocusedCocoa(window))
        updateCursorMode(window);
    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwSetCursorModeCocoa(_GLFWwindow* window, int mode)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
const char* _glfwGetScancodeNameCocoa(int scancode)
{
    @autoreleasepool {

    if (scancode < 0 || scancode > 0xff ||
        _glfw.ns.keycodes[scancode] == GLFW_KEY_UNKNOWN)
    {
        _glfwInputError(GLFW_INVALID_VALUE, "Invalid scancode %i", scancode);
        return NULL;
    }

    const int key = _glfw.ns.keycodes[scancode];

    UInt32 deadKeyState = 0;
    UniChar characters[4];
    UniCharCount characterCount = 0;

    if (UCKeyTranslate([(NSData*) _glfw.ns.unicodeData bytes],
                       scancode,
                       kUCKeyActionDisplay,
                       0,
                       LMGetKbdType(),
                       kUCKeyTranslateNoDeadKeysBit,
                       &deadKeyState,
                       sizeof(characters) / sizeof(characters[0]),
                       &characterCount,
                       characters) != noErr)
    {
        return NULL;
    }

    if (!characterCount)
        return NULL;

    CFStringRef string = CFStringCreateWithCharactersNoCopy(kCFAllocatorDefault,
                                                            characters,
                                                            characterCount,
                                                            kCFAllocatorNull);
    CFStringGetCString(string,
                       _glfw.ns.keynames[key],
                       sizeof(_glfw.ns.keynames[key]),
                       kCFStringEncodingUTF8);
    CFRelease(string);

    return _glfw.ns.keynames[key];

    } // autoreleasepool
}
#else // NEW_APPLE
const char* _glfwGetScancodeNameCocoa(int scancode)
{
    KFX_DBG("NOT IMPLEMENTED - returning '0'");
    return "0";
}
#endif // NEW_APPLE

#if NEW_APPLE
int _glfwGetKeyScancodeCocoa(int key)
{
    return _glfw.ns.scancodes[key];
}
#else // NEW_APPLE
int _glfwGetKeyScancodeCocoa(int key)
{
    KFX_DBG("NOT IMPLEMENTED returning 0");
    return 0;
}
#endif // NEW_APPLE

#if NEW_APPLE
GLFWbool _glfwCreateCursorCocoa(_GLFWcursor* cursor,
                                const GLFWimage* image,
                                int xhot, int yhot)
{
    @autoreleasepool {

    NSImage* native;
    NSBitmapImageRep* rep;

    rep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
                      pixelsWide:image->width
                      pixelsHigh:image->height
                   bitsPerSample:8
                 samplesPerPixel:4
                        hasAlpha:YES
                        isPlanar:NO
                  colorSpaceName:NSCalibratedRGBColorSpace
                    bitmapFormat:NSBitmapFormatAlphaNonpremultiplied
                     bytesPerRow:image->width * 4
                    bitsPerPixel:32];

    if (rep == nil)
        return GLFW_FALSE;

    memcpy([rep bitmapData], image->pixels, image->width * image->height * 4);

    native = [[NSImage alloc] initWithSize:NSMakeSize(image->width, image->height)];
    [native addRepresentation:rep];

    cursor->ns.object = [[NSCursor alloc] initWithImage:native
                                                hotSpot:NSMakePoint(xhot, yhot)];

    [native release];
    [rep release];

    if (cursor->ns.object == nil)
        return GLFW_FALSE;

    return GLFW_TRUE;

    } // autoreleasepool
}
#else // NEW_APPLE
GLFWbool _glfwCreateCursorCocoa(_GLFWcursor* cursor,
                                const GLFWimage* image,
                                int xhot, int yhot)
{
    KFX_DBG("NOT IMPLEMENTED - returning false");
    return GLFW_FALSE;
}
#endif // NEW_APPLE

#if NEW_APPLE
GLFWbool _glfwCreateStandardCursorCocoa(_GLFWcursor* cursor, int shape)
{
    @autoreleasepool {

    SEL cursorSelector = NULL;

    // HACK: Try to use a private message
    switch (shape)
    {
        case GLFW_RESIZE_EW_CURSOR:
            cursorSelector = NSSelectorFromString(@"_windowResizeEastWestCursor");
            break;
        case GLFW_RESIZE_NS_CURSOR:
            cursorSelector = NSSelectorFromString(@"_windowResizeNorthSouthCursor");
            break;
        case GLFW_RESIZE_NWSE_CURSOR:
            cursorSelector = NSSelectorFromString(@"_windowResizeNorthWestSouthEastCursor");
            break;
        case GLFW_RESIZE_NESW_CURSOR:
            cursorSelector = NSSelectorFromString(@"_windowResizeNorthEastSouthWestCursor");
            break;
    }

    if (cursorSelector && [NSCursor respondsToSelector:cursorSelector])
    {
        id object = [NSCursor performSelector:cursorSelector];
        if ([object isKindOfClass:[NSCursor class]])
            cursor->ns.object = object;
    }

    if (!cursor->ns.object)
    {
        switch (shape)
        {
            case GLFW_ARROW_CURSOR:
                cursor->ns.object = [NSCursor arrowCursor];
                break;
            case GLFW_IBEAM_CURSOR:
                cursor->ns.object = [NSCursor IBeamCursor];
                break;
            case GLFW_CROSSHAIR_CURSOR:
                cursor->ns.object = [NSCursor crosshairCursor];
                break;
            case GLFW_POINTING_HAND_CURSOR:
                cursor->ns.object = [NSCursor pointingHandCursor];
                break;
            case GLFW_RESIZE_EW_CURSOR:
                cursor->ns.object = [NSCursor resizeLeftRightCursor];
                break;
            case GLFW_RESIZE_NS_CURSOR:
                cursor->ns.object = [NSCursor resizeUpDownCursor];
                break;
            case GLFW_RESIZE_ALL_CURSOR:
                cursor->ns.object = [NSCursor closedHandCursor];
                break;
            case GLFW_NOT_ALLOWED_CURSOR:
                cursor->ns.object = [NSCursor operationNotAllowedCursor];
                break;
        }
    }

    if (!cursor->ns.object)
    {
        _glfwInputError(GLFW_CURSOR_UNAVAILABLE,
                        "Cocoa: Standard cursor shape unavailable");
        return GLFW_FALSE;
    }

    [cursor->ns.object retain];
    return GLFW_TRUE;

    } // autoreleasepool
}
#else // NEW_APPLE
GLFWbool _glfwCreateStandardCursorCocoa(_GLFWcursor* cursor, int shape)
{
    KFX_DBG("NOT IMPLEMENTED - returning false");
    return GLFW_FALSE;
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwDestroyCursorCocoa(_GLFWcursor* cursor)
{
    @autoreleasepool {
    if (cursor->ns.object)
        [(NSCursor*) cursor->ns.object release];
    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwDestroyCursorCocoa(_GLFWcursor* cursor)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwSetCursorCocoa(_GLFWwindow* window, _GLFWcursor* cursor)
{
    @autoreleasepool {
    if (cursorInContentArea(window))
        updateCursorImage(window);
    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwSetCursorCocoa(_GLFWwindow* window, _GLFWcursor* cursor)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwSetClipboardStringCocoa(const char* string)
{
    @autoreleasepool {
    NSPasteboard* pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:@[NSPasteboardTypeString] owner:nil];
    [pasteboard setString:@(string) forType:NSPasteboardTypeString];
    } // autoreleasepool
}
#else // NEW_APPLE
void _glfwSetClipboardStringCocoa(const char* string)
{
    KFX_DBG("NOT IMPLEMENTED");
}
#endif // NEW_APPLE

#if NEW_APPLE
const char* _glfwGetClipboardStringCocoa(void)
{
    @autoreleasepool {

    NSPasteboard* pasteboard = [NSPasteboard generalPasteboard];

    if (![[pasteboard types] containsObject:NSPasteboardTypeString])
    {
        _glfwInputError(GLFW_FORMAT_UNAVAILABLE,
                        "Cocoa: Failed to retrieve string from pasteboard");
        return NULL;
    }

    NSString* object = [pasteboard stringForType:NSPasteboardTypeString];
    if (!object)
    {
        _glfwInputError(GLFW_PLATFORM_ERROR,
                        "Cocoa: Failed to retrieve object from pasteboard");
        return NULL;
    }

    _glfw_free(_glfw.ns.clipboardString);
    _glfw.ns.clipboardString = _glfw_strdup([object UTF8String]);

    return _glfw.ns.clipboardString;

    } // autoreleasepool
}
#else // NEW_APPLE
const char* _glfwGetClipboardStringCocoa(void)
{
    KFX_DBG("NOT IMPLEMENTED - returning \"\"");
    return "";
}
#endif // NEW_APPLE

#if NEW_APPLE
EGLenum _glfwGetEGLPlatformCocoa(EGLint** attribs)
{
    if (_glfw.egl.ANGLE_platform_angle)
    {
        int type = 0;

        if (_glfw.egl.ANGLE_platform_angle_opengl)
        {
            if (_glfw.hints.init.angleType == GLFW_ANGLE_PLATFORM_TYPE_OPENGL)
                type = EGL_PLATFORM_ANGLE_TYPE_OPENGL_ANGLE;
        }

        if (_glfw.egl.ANGLE_platform_angle_metal)
        {
            if (_glfw.hints.init.angleType == GLFW_ANGLE_PLATFORM_TYPE_METAL)
                type = EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE;
        }

        if (type)
        {
            *attribs = _glfw_calloc(3, sizeof(EGLint));
            (*attribs)[0] = EGL_PLATFORM_ANGLE_TYPE_ANGLE;
            (*attribs)[1] = type;
            (*attribs)[2] = EGL_NONE;
            return EGL_PLATFORM_ANGLE_ANGLE;
        }
    }

    return 0;
}
#else // NEW_APPLE
EGLenum _glfwGetEGLPlatformCocoa(EGLint** attribs)
{
    KFX_DBG("NOT IMPLEMENTED - returning 0");
    return 0;
}
#endif // NEW_APPLE

EGLNativeDisplayType _glfwGetEGLNativeDisplayCocoa(void)
{
    return EGL_DEFAULT_DISPLAY;
}

#if NEW_APPLE
EGLNativeWindowType _glfwGetEGLNativeWindowCocoa(_GLFWwindow* window)
{
    return window->ns.layer;
}
#else // NEW_APPLE
EGLNativeWindowType _glfwGetEGLNativeWindowCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED - returning NULL");
    return NULL;
}
#endif // NEW_APPLE

#if NEW_APPLE
void _glfwGetRequiredInstanceExtensionsCocoa(char** extensions)
{
    if (_glfw.vk.KHR_surface && _glfw.vk.EXT_metal_surface)
    {
        extensions[0] = "VK_KHR_surface";
        extensions[1] = "VK_EXT_metal_surface";
    }
    else if (_glfw.vk.KHR_surface && _glfw.vk.MVK_macos_surface)
    {
        extensions[0] = "VK_KHR_surface";
        extensions[1] = "VK_MVK_macos_surface";
    }
}
#else // NEW_APPLE
void _glfwGetRequiredInstanceExtensionsCocoa(char** extensions)
{
    KFX_DBG("NOT IMPLEMENTED - not doing anything");
}
#endif // NEW_APPLE

GLFWbool _glfwGetPhysicalDevicePresentationSupportCocoa(VkInstance instance,
                                                        VkPhysicalDevice device,
                                                        uint32_t queuefamily)
{
    return GLFW_TRUE;
}

#if NEW_APPLE
VkResult _glfwCreateWindowSurfaceCocoa(VkInstance instance,
                                       _GLFWwindow* window,
                                       const VkAllocationCallbacks* allocator,
                                       VkSurfaceKHR* surface)
{
    @autoreleasepool {

#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101100
    // HACK: Dynamically load Core Animation to avoid adding an extra
    //       dependency for the majority who don't use MoltenVK
    NSBundle* bundle = [NSBundle bundleWithPath:@"/System/Library/Frameworks/QuartzCore.framework"];
    if (!bundle)
    {
        _glfwInputError(GLFW_PLATFORM_ERROR,
                        "Cocoa: Failed to find QuartzCore.framework");
        return VK_ERROR_EXTENSION_NOT_PRESENT;
    }

    // NOTE: Create the layer here as makeBackingLayer should not return nil
    window->ns.layer = [[bundle classNamed:@"CAMetalLayer"] layer];
    if (!window->ns.layer)
    {
        _glfwInputError(GLFW_PLATFORM_ERROR,
                        "Cocoa: Failed to create layer for view");
        return VK_ERROR_EXTENSION_NOT_PRESENT;
    }

    if (window->ns.retina)
        [window->ns.layer setContentsScale:[window->ns.object backingScaleFactor]];

    [window->ns.view setLayer:window->ns.layer];
    [window->ns.view setWantsLayer:YES];

    VkResult err;

    if (_glfw.vk.EXT_metal_surface)
    {
        VkMetalSurfaceCreateInfoEXT sci;

        PFN_vkCreateMetalSurfaceEXT vkCreateMetalSurfaceEXT;
        vkCreateMetalSurfaceEXT = (PFN_vkCreateMetalSurfaceEXT)
            vkGetInstanceProcAddr(instance, "vkCreateMetalSurfaceEXT");
        if (!vkCreateMetalSurfaceEXT)
        {
            _glfwInputError(GLFW_API_UNAVAILABLE,
                            "Cocoa: Vulkan instance missing VK_EXT_metal_surface extension");
            return VK_ERROR_EXTENSION_NOT_PRESENT;
        }

        memset(&sci, 0, sizeof(sci));
        sci.sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
        sci.pLayer = window->ns.layer;

        err = vkCreateMetalSurfaceEXT(instance, &sci, allocator, surface);
    }
    else
    {
        VkMacOSSurfaceCreateInfoMVK sci;

        PFN_vkCreateMacOSSurfaceMVK vkCreateMacOSSurfaceMVK;
        vkCreateMacOSSurfaceMVK = (PFN_vkCreateMacOSSurfaceMVK)
            vkGetInstanceProcAddr(instance, "vkCreateMacOSSurfaceMVK");
        if (!vkCreateMacOSSurfaceMVK)
        {
            _glfwInputError(GLFW_API_UNAVAILABLE,
                            "Cocoa: Vulkan instance missing VK_MVK_macos_surface extension");
            return VK_ERROR_EXTENSION_NOT_PRESENT;
        }

        memset(&sci, 0, sizeof(sci));
        sci.sType = VK_STRUCTURE_TYPE_MACOS_SURFACE_CREATE_INFO_MVK;
        sci.pView = window->ns.view;

        err = vkCreateMacOSSurfaceMVK(instance, &sci, allocator, surface);
    }

    if (err)
    {
        _glfwInputError(GLFW_PLATFORM_ERROR,
                        "Cocoa: Failed to create Vulkan surface: %s",
                        _glfwGetVulkanResultString(err));
    }

    return err;
#else
    return VK_ERROR_EXTENSION_NOT_PRESENT;
#endif

    } // autoreleasepool
}
#else // NEW_APPLE
VkResult _glfwCreateWindowSurfaceCocoa(VkInstance instance,
                                       _GLFWwindow* window,
                                       const VkAllocationCallbacks* allocator,
                                       VkSurfaceKHR* surface)
{
    KFX_DBG("NOT IMPLEMENTED - returning NOT_PRESENT");
    return VK_ERROR_EXTENSION_NOT_PRESENT;
}
#endif // NEW_APPLE

//////////////////////////////////////////////////////////////////////////
//////                        GLFW native API                       //////
//////////////////////////////////////////////////////////////////////////
#if NEW_APPLE
GLFWAPI id glfwGetCocoaWindow(GLFWwindow* handle)
{
    _GLFWwindow* window = (_GLFWwindow*) handle;
    _GLFW_REQUIRE_INIT_OR_RETURN(nil);

    if (_glfw.platform.platformID != GLFW_PLATFORM_COCOA)
    {
        _glfwInputError(GLFW_PLATFORM_UNAVAILABLE,
                        "Cocoa: Platform not initialized");
        return NULL;
    }

    return window->ns.object;
}
#else // NEW_APPLE
GLFWAPI id glfwGetCocoaWindow(GLFWwindow* handle)
{
    KFX_DBG("NOT IMPLEMENTED - returning NULL");
    return NULL;
}
#endif // NEW_APPLE