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

#if MAC_OS_X_VERSION_MIN_REQUIRED < 1060
//------------------------------------------------------------------------
// GLFW window class
//------------------------------------------------------------------------

@class CocoaWindowListener;

@interface GLFWWindow : NSWindow {
    CocoaWindowListener* listener;
}
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
//   if (![delegate isKindOfClass:[CocoaWindowListener class]]) {
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

typedef enum
{
    PENDING_OPERATION_NONE,
    PENDING_OPERATION_ENTER_FULLSCREEN,
    PENDING_OPERATION_LEAVE_FULLSCREEN,
    PENDING_OPERATION_MINIMIZE
} PendingWindowOperation;

@interface CocoaWindowListener : NSResponder {

    GLFWWindow* window;
    BOOL observingVisible;
    BOOL wasCtrlLeft;
    BOOL wasVisible;
    BOOL isFullscreenSpace;
    BOOL inFullscreenTransition;
    PendingWindowOperation pendingWindowOperation;
    BOOL isMoving;
    int pendingWindowWarpX, pendingWindowWarpY;
}

-(void) listen:(GLFWWindow*) data;
-(void) pauseVisibleObservation;
-(void) resumeVisibleObservation;
-(BOOL) setFullscreenSpace:(BOOL) state;
-(BOOL) isInFullscreenSpace;
-(BOOL) isInFullscreenSpaceTransition;
-(void) addPendingWindowOperation:(PendingWindowOperation) operation;
-(void) close;

-(BOOL) isMoving;
-(void) setPendingMoveX:(int)x Y:(int)y;
-(void) windowDidFinishMoving;

/* Window delegate functionality */
-(BOOL) windowShouldClose:(id) sender;
-(void) windowDidExpose:(NSNotification*) aNotification;
-(void) windowDidMove:(NSNotification*) aNotification;
-(void) windowDidResize:(NSNotification*) aNotification;
-(void) windowDidMiniaturize:(NSNotification*) aNotification;
-(void) windowDidDeminiaturize:(NSNotification*) aNotification;
-(void) windowDidBecomeKey:(NSNotification*) aNotification;
-(void) windowDidResignKey:(NSNotification*) aNotification;

/* Window event handling */
-(void) mouseDown:(NSEvent*) theEvent;
-(void) rightMouseDown:(NSEvent*) theEvent;
-(void) otherMouseDown:(NSEvent*) theEvent;
-(void) mouseUp:(NSEvent*) theEvent;
-(void) rightMouseUp:(NSEvent*) theEvent;
-(void) otherMouseUp:(NSEvent*) theEvent;
-(void) mouseMoved:(NSEvent*) theEvent;
-(void) mouseDragged:(NSEvent*) theEvent;
-(void) rightMouseDragged:(NSEvent*) theEvent;
-(void) otherMouseDragged:(NSEvent*) theEvent;
-(void) scrollWheel:(NSEvent*) theEvent;
-(void) touchesBeganWithEvent:(NSEvent*) theEvent;
-(void) touchesMovedWithEvent:(NSEvent*) theEvent;
-(void) touchesEndedWithEvent:(NSEvent*) theEvent;
-(void) touchesCancelledWithEvent:(NSEvent*) theEvent;

@end


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

@implementation CocoaWindowListener

- (void)listen:(GLFWWindow *)win
{
    NSNotificationCenter *center;
    NSView *view = [window contentView];

    window = win;
    observingVisible = YES;
    wasCtrlLeft = NO;
    wasVisible = [window isVisible];
    isFullscreenSpace = NO;
    inFullscreenTransition = NO;
    pendingWindowOperation = PENDING_OPERATION_NONE;
    isMoving = NO;

    center = [NSNotificationCenter defaultCenter];

    if ([window delegate] != nil) {
        [center addObserver:self selector:@selector(windowDidExpose:) name:NSWindowDidExposeNotification object:window];
        [center addObserver:self selector:@selector(windowDidMove:) name:NSWindowDidMoveNotification object:window];
        [center addObserver:self selector:@selector(windowDidResize:) name:NSWindowDidResizeNotification object:window];
        [center addObserver:self selector:@selector(windowDidMiniaturize:) name:NSWindowDidMiniaturizeNotification object:window];
        [center addObserver:self selector:@selector(windowDidDeminiaturize:) name:NSWindowDidDeminiaturizeNotification object:window];
        [center addObserver:self selector:@selector(windowDidBecomeKey:) name:NSWindowDidBecomeKeyNotification object:window];
        [center addObserver:self selector:@selector(windowDidResignKey:) name:NSWindowDidResignKeyNotification object:window];
    } else {
        [window setDelegate:self];
    }

    /* Haven't found a delegate / notification that triggers when the window is
     * ordered out (is not visible any more). You can be ordered out without
     * minimizing, so DidMiniaturize doesn't work. (e.g. -[NSWindow orderOut:])
     */
    [window addObserver:self
             forKeyPath:@"visible"
                options:NSKeyValueObservingOptionNew
                context:NULL];

    [window setNextResponder:self];
    [window setAcceptsMouseMovedEvents:YES];

    [view setNextResponder:self];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
}

-(void) pauseVisibleObservation
{
}

-(void) resumeVisibleObservation
{
}

-(BOOL) setFullscreenSpace:(BOOL) state
{
}

-(BOOL) isInFullscreenSpace
{
    return isFullscreenSpace;
}

-(BOOL) isInFullscreenSpaceTransition
{
    return inFullscreenTransition;
}

-(void) addPendingWindowOperation:(PendingWindowOperation) operation
{
    pendingWindowOperation = operation;
}

- (void)close
{
    NSNotificationCenter *center;
    NSView *view = [window contentView];
    NSArray *windows = nil;

    center = [NSNotificationCenter defaultCenter];

    if ([window delegate] != self) {
        [center removeObserver:self name:NSWindowDidExposeNotification object:window];
        [center removeObserver:self name:NSWindowDidMoveNotification object:window];
        [center removeObserver:self name:NSWindowDidResizeNotification object:window];
        [center removeObserver:self name:NSWindowDidMiniaturizeNotification object:window];
        [center removeObserver:self name:NSWindowDidDeminiaturizeNotification object:window];
        [center removeObserver:self name:NSWindowDidBecomeKeyNotification object:window];
        [center removeObserver:self name:NSWindowDidResignKeyNotification object:window];
    } else {
        [window setDelegate:nil];
    }

    [window removeObserver:self forKeyPath:@"visible"];

    if ([window nextResponder] == self) {
        [window setNextResponder:nil];
    }
    if ([view nextResponder] == self) {
        [view setNextResponder:nil];
    }

    /* Make the next window in the z-order Key. If we weren't the foreground
       when closed, this is a no-op.
       !!! FIXME: Note that this is a hack, and there are corner cases where
       !!! FIXME:  this fails (such as the About box). The typical nib+RunLoop
       !!! FIXME:  handles this for Cocoa apps, but we bypass all that in SDL.
       !!! FIXME:  We should remove this code when we find a better way to
       !!! FIXME:  have the system do this for us. See discussion in
       !!! FIXME:   http://bugzilla.libsdl.org/show_bug.cgi?id=1825
    */
    windows = [NSApp orderedWindows];
    /* old way to iterate */
    int i;
    for (i = 0; i < [windows count]; i++) {
        NSWindow *win = [windows objectAtIndex:i];
        if (win == window) {
            continue;
        }

        [win makeKeyAndOrderFront:self];
        break;
    }
}

- (BOOL)isMoving
{
    return isMoving;
}

-(void) setPendingMoveX:(int)x Y:(int)y
{
    pendingWindowWarpX = x;
    pendingWindowWarpY = y;
}

- (void)windowDidFinishMoving
{
}

- (BOOL)windowShouldClose:(id)sender
{
    return NO;
}

- (void)windowDidExpose:(NSNotification *)aNotification
{
}

- (void)windowWillMove:(NSNotification *)aNotification
{
}

- (void)windowDidMove:(NSNotification *)aNotification
{
}

- (void)windowDidResize:(NSNotification *)aNotification
{
}

- (void)windowDidMiniaturize:(NSNotification *)aNotification
{
}

- (void)windowDidDeminiaturize:(NSNotification *)aNotification
{
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
}

- (void)windowDidResignKey:(NSNotification *)aNotification
{
}

- (void)windowWillEnterFullScreen:(NSNotification *)aNotification
{
}

- (void)windowDidEnterFullScreen:(NSNotification *)aNotification
{
}

- (void)windowWillExitFullScreen:(NSNotification *)aNotification
{
    isFullscreenSpace = NO;
    inFullscreenTransition = YES;
}

- (void)windowDidExitFullScreen:(NSNotification *)aNotification
{
}

/* We'll respond to key events by doing nothing so we don't beep.
 * We could handle key messages here, but we lose some in the NSApp dispatch,
 * where they get converted to action messages, etc.
 */
- (void)flagsChanged:(NSEvent *)theEvent
{
    /*Cocoa_HandleKeyEvent(SDL_GetVideoDevice(), theEvent);*/
}
- (void)keyDown:(NSEvent *)theEvent
{
    /*Cocoa_HandleKeyEvent(SDL_GetVideoDevice(), theEvent);*/
}
- (void)keyUp:(NSEvent *)theEvent
{
    /*Cocoa_HandleKeyEvent(SDL_GetVideoDevice(), theEvent);*/
}

/* We'll respond to selectors by doing nothing so we don't beep.
 * The escape key gets converted to a "cancel" selector, etc.
 */
- (void)doCommandBySelector:(SEL)aSelector
{
    /*NSLog(@"doCommandBySelector: %@\n", NSStringFromSelector(aSelector));*/
}

- (void)mouseDown:(NSEvent *)theEvent
{
}

- (void)rightMouseDown:(NSEvent *)theEvent
{
}

- (void)otherMouseDown:(NSEvent *)theEvent
{
}

- (void)mouseUp:(NSEvent *)theEvent
{
}

- (void)rightMouseUp:(NSEvent *)theEvent
{
}

- (void)otherMouseUp:(NSEvent *)theEvent
{
}

- (void)mouseMoved:(NSEvent *)theEvent
{
}

- (void)mouseDragged:(NSEvent *)theEvent
{
    [self mouseMoved:theEvent];
}

- (void)rightMouseDragged:(NSEvent *)theEvent
{
    [self mouseMoved:theEvent];
}

- (void)otherMouseDragged:(NSEvent *)theEvent
{
    [self mouseMoved:theEvent];
}

- (void)scrollWheel:(NSEvent *)theEvent
{
}
@end

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
        ADD_ATTRIB(NSOpenGLPFAStereo);
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

//////////////////////////////////////////////////////////////////////////
//////                       GLFW platform API                      //////
//////////////////////////////////////////////////////////////////////////

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

    GLFWWindow* nswindow = [[GLFWWindow alloc] initWithContentRect:rect styleMask:style backing:NSBackingStoreBuffered defer:NO screen:screen];
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

    // TODO KFX: Cleanup later?
    /* Create an event listener for the window */
    nswindow->listener = [[CocoaWindowListener alloc] init];

    /* Set up the listener after we create the view */
    [nswindow->listener listen:nswindow];

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

void _glfwDestroyWindowCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");

    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    [pool release];
}

void _glfwSetWindowTitleCocoa(_GLFWwindow* window, const char* title)
{
    KFX_DBG("NOT IMPLEMENTED");
}

void _glfwSetWindowIconCocoa(_GLFWwindow* window,
                             int count, const GLFWimage* images)
{
    _glfwInputError(GLFW_FEATURE_UNAVAILABLE,
                    "Cocoa: Regular windows do not have icons on macOS");
}

void _glfwGetWindowPosCocoa(_GLFWwindow* window, int* xpos, int* ypos)
{
    KFX_DBG("NOT IMPLEMENTED - returning [0, 0]");
    if (xpos)
        *xpos = 0;
    if (ypos)
        *ypos = 0;
}

void _glfwSetWindowPosCocoa(_GLFWwindow* window, int x, int y)
{
    KFX_DBG("NOT IMPLEMENTED");
}

void _glfwGetWindowSizeCocoa(_GLFWwindow* window, int* width, int* height)
{
    KFX_DBG("NOT IMPLEMENTED - returning [800, 600]");
    if (width)
        *width = 800;
    if (height)
        *height = 600;
}

void _glfwSetWindowSizeCocoa(_GLFWwindow* window, int width, int height)
{
    KFX_DBG("NOT IMPLEMENTED");
}

void _glfwSetWindowSizeLimitsCocoa(_GLFWwindow* window,
                                   int minwidth, int minheight,
                                   int maxwidth, int maxheight)
{
    KFX_DBG("NOT IMPLEMENTED");
}

void _glfwSetWindowAspectRatioCocoa(_GLFWwindow* window, int numer, int denom)
{
    KFX_DBG("NOT IMPLEMENTED");
}

void _glfwGetFramebufferSizeCocoa(_GLFWwindow* window, int* width, int* height)
{
    KFX_DBG("NOT IMPLEMENTED - returning [800, 600]");
    if (width)
        *width = 800;
    if (height)
        *height = 600;
}

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

void _glfwGetWindowContentScaleCocoa(_GLFWwindow* window,
                                     float* xscale, float* yscale)
{
    KFX_DBG("NOT IMPLEMENTED - returning [1, 1]");
    if (xscale)
        *xscale = 1;
    if (yscale)
        *yscale = 1;
}

void _glfwIconifyWindowCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
}

void _glfwRestoreWindowCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
}

void _glfwMaximizeWindowCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
}

void _glfwShowWindowCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
}

void _glfwHideWindowCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
}

void _glfwRequestWindowAttentionCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
}

void _glfwFocusWindowCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
}

void _glfwSetWindowMonitorCocoa(_GLFWwindow* window,
                                _GLFWmonitor* monitor,
                                int xpos, int ypos,
                                int width, int height,
                                int refreshRate)
{
    KFX_DBG("NOT IMPLEMENTED");
}

GLFWbool _glfwWindowFocusedCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
    return GLFW_TRUE;
}

GLFWbool _glfwWindowIconifiedCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
    return GLFW_TRUE;
}

GLFWbool _glfwWindowVisibleCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
    return GLFW_TRUE;
}

GLFWbool _glfwWindowMaximizedCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
    return GLFW_TRUE;
}

GLFWbool _glfwWindowHoveredCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
    return GLFW_TRUE;
}

GLFWbool _glfwFramebufferTransparentCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED");
    return GLFW_TRUE;
}

void _glfwSetWindowResizableCocoa(_GLFWwindow* window, GLFWbool enabled)
{
    KFX_DBG("NOT IMPLEMENTED");
}

void _glfwSetWindowDecoratedCocoa(_GLFWwindow* window, GLFWbool enabled)
{
    KFX_DBG("NOT IMPLEMENTED");
}

void _glfwSetWindowFloatingCocoa(_GLFWwindow* window, GLFWbool enabled)
{
    KFX_DBG("NOT IMPLEMENTED");
}

void _glfwSetWindowMousePassthroughCocoa(_GLFWwindow* window, GLFWbool enabled)
{
    KFX_DBG("NOT IMPLEMENTED");
}

float _glfwGetWindowOpacityCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED - returning 1");
    return 1.0f;
}

void _glfwSetWindowOpacityCocoa(_GLFWwindow* window, float opacity)
{
    KFX_DBG("NOT IMPLEMENTED");
}

void _glfwSetRawMouseMotionCocoa(_GLFWwindow *window, GLFWbool enabled)
{
    _glfwInputError(GLFW_FEATURE_UNIMPLEMENTED,
                    "Cocoa: Raw mouse motion not yet implemented");
}

GLFWbool _glfwRawMouseMotionSupportedCocoa(void)
{
    return GLFW_FALSE;
}

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

void _glfwWaitEventsCocoa(void)
{
    KFX_DBG("NOT IMPLEMENTED");
}

void _glfwWaitEventsTimeoutCocoa(double timeout)
{
    KFX_DBG("NOT IMPLEMENTED");
}

void _glfwPostEmptyEventCocoa(void)
{
    KFX_DBG("NOT IMPLEMENTED");
}

void _glfwGetCursorPosCocoa(_GLFWwindow* window, double* xpos, double* ypos)
{
    KFX_DBG("NOT IMPLEMENTED - returning [400, 300]");
    if (xpos)
        *xpos = 400;
    if (ypos)
        *ypos = 300;
}

void _glfwSetCursorPosCocoa(_GLFWwindow* window, double x, double y)
{
    KFX_DBG("NOT IMPLEMENTED");
}

void _glfwSetCursorModeCocoa(_GLFWwindow* window, int mode)
{
    KFX_DBG("NOT IMPLEMENTED");
}

const char* _glfwGetScancodeNameCocoa(int scancode)
{
    KFX_DBG("NOT IMPLEMENTED - returning '0'");
    return "0";
}

int _glfwGetKeyScancodeCocoa(int key)
{
    KFX_DBG("NOT IMPLEMENTED returning 0");
    return 0;
}

GLFWbool _glfwCreateCursorCocoa(_GLFWcursor* cursor,
                                const GLFWimage* image,
                                int xhot, int yhot)
{
    KFX_DBG("NOT IMPLEMENTED - returning false");
    return GLFW_FALSE;
}

GLFWbool _glfwCreateStandardCursorCocoa(_GLFWcursor* cursor, int shape)
{
    KFX_DBG("NOT IMPLEMENTED - returning false");
    return GLFW_FALSE;
}

void _glfwDestroyCursorCocoa(_GLFWcursor* cursor)
{
    KFX_DBG("NOT IMPLEMENTED");
}

void _glfwSetCursorCocoa(_GLFWwindow* window, _GLFWcursor* cursor)
{
    KFX_DBG("NOT IMPLEMENTED");
}

void _glfwSetClipboardStringCocoa(const char* string)
{
    KFX_DBG("NOT IMPLEMENTED");
}

const char* _glfwGetClipboardStringCocoa(void)
{
    KFX_DBG("NOT IMPLEMENTED - returning \"\"");
    return "";
}

EGLenum _glfwGetEGLPlatformCocoa(EGLint** attribs)
{
    KFX_DBG("NOT IMPLEMENTED - returning 0");
    return 0;
}

EGLNativeDisplayType _glfwGetEGLNativeDisplayCocoa(void)
{
    return EGL_DEFAULT_DISPLAY;
}

EGLNativeWindowType _glfwGetEGLNativeWindowCocoa(_GLFWwindow* window)
{
    KFX_DBG("NOT IMPLEMENTED - returning NULL");
    return NULL;
}

void _glfwGetRequiredInstanceExtensionsCocoa(char** extensions)
{
    KFX_DBG("NOT IMPLEMENTED - not doing anything");
}

GLFWbool _glfwGetPhysicalDevicePresentationSupportCocoa(VkInstance instance,
                                                        VkPhysicalDevice device,
                                                        uint32_t queuefamily)
{
    return GLFW_TRUE;
}

VkResult _glfwCreateWindowSurfaceCocoa(VkInstance instance,
                                       _GLFWwindow* window,
                                       const VkAllocationCallbacks* allocator,
                                       VkSurfaceKHR* surface)
{
    KFX_DBG("NOT IMPLEMENTED - returning NOT_PRESENT");
    return VK_ERROR_EXTENSION_NOT_PRESENT;
}
//////////////////////////////////////////////////////////////////////////
//////                        GLFW native API                       //////
//////////////////////////////////////////////////////////////////////////
GLFWAPI id glfwGetCocoaWindow(GLFWwindow* handle)
{
    KFX_DBG("NOT IMPLEMENTED - returning NULL");
    return NULL;
}
#endif // MAC_OS_X_VERSION_MIN_REQUIRED < 1060
