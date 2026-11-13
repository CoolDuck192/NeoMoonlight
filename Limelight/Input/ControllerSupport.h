//
//  ControllerSupport.h
//  Moonlight
//
//  Created by Cameron Gutman on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "Controller.h"
#import <UIKit/UIKit.h>

// It's in Swift's hands now
@class TemporarySettings;

@class StreamConfiguration;

@class OnScreenControls;

@protocol ControllerSupportDelegate <NSObject>

- (void) gamepadPresenceChanged;
- (void) mousePresenceChanged;
- (void) streamExitRequested;

@end

@interface ControllerSupport : NSObject

-(id) initWithConfig:(StreamConfiguration*)streamConfig delegate:(id<ControllerSupportDelegate>)delegate;
-(void) registerMouseCallbacks:(GCMouse*)mouse API_AVAILABLE(ios(14.0));
-(void) unregisterMouseCallbacks:(GCMouse*)mouse API_AVAILABLE(ios(14.0));
-(void) connectionEstablished;

-(void) initAutoOnScreenControlMode:(OnScreenControls*)osc;
-(void) cleanup;
-(Controller*) getOscController;

-(void) updateLeftStick:(Controller*)controller x:(short)x y:(short)y;
-(void) updateRightStick:(Controller*)controller x:(short)x y:(short)y;

-(void) updateLeftTrigger:(Controller*)controller left:(unsigned char)left;
-(void) updateRightTrigger:(Controller*)controller right:(unsigned char)right;
-(void) updateTriggers:(Controller*)controller left:(unsigned char)left right:(unsigned char)right;

-(void) updateButtonFlags:(Controller*)controller flags:(int)flags;
-(void) setButtonFlag:(Controller*)controller flags:(int)flags;
-(void) clearButtonFlag:(Controller*)controller flags:(int)flags;

-(void) updateFinished:(Controller*)controller;

-(void) rumble:(unsigned short)controllerNumber lowFreqMotor:(unsigned short)lowFreqMotor highFreqMotor:(unsigned short)highFreqMotor;
-(void) rumbleTriggers:(uint16_t)controllerNumber leftTrigger:(uint16_t)leftTrigger rightTrigger:(uint16_t)rightTrigger;
-(void) setMotionEventState:(uint16_t)controllerNumber motionType:(uint8_t)motionType reportRateHz:(uint16_t)reportRateHz;
-(void) setControllerLed:(uint16_t)controllerNumber r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b;

+(int) getConnectedGamepadMask:(StreamConfiguration*)streamConfig settings:(TemporarySettings* _Nullable)settings;
+(int) getGamepadMaskForSlot:(int)slot;

-(void) setSwapABXYButtons:(BOOL)swap;
-(void) setReportControllerAsXbox:(BOOL)reportAsXbox;

-(NSUInteger) getConnectedGamepadCount;

- (void) attachGCEventInteractionToView:(UIView *)view;
- (void) detachGCEventInteractionFromView:(UIView *)view;

/// Sample digital input on input queue (~30 Hz + events); resample analog axes at 60 Hz on send queue.
- (void) setInputSyncEnabled:(BOOL)enabled;
/// Pushes current gamepad state to the host immediately (e.g. entering Controller mode).
- (void) refreshControllerStates;
/// Re-attaches gamepad value handlers after foreground (OS may clear physicalInputProfile callbacks).
- (void) restoreGamepadHandlersAfterForeground;
/// Sends a neutral gamepad packet (releases buttons/sticks) without re-enabling sync.
- (void) releaseHeldInputsToHost;

/// visionOS only: forward GCMouse scroll-wheel axes to the host. Default NO. Only the Curved view sets it;
/// Flat and Classic already scroll through UIKit recognisers and would send twice. One instance forwards at
/// a time: the last one that set this to YES, until it sets NO or is cleaned up.
@property (nonatomic) BOOL forwardsGCMouseScroll;
/// Wheel notches sent to the host per GCMouse scroll event (visionOS scroll values are accelerated, so their
/// size is not used). Negative reverses direction. 0 (the default) is treated as 1.
@property (nonatomic) float gcMouseScrollScale;

@end
