#import <Cocoa/Cocoa.h>
#import <GLKit/GLKit.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreFoundation/CoreFoundation.h>
#import <ImageIO/ImageIO.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>


@class AVCaptureVideoPreviewLayer;
@class AVCaptureSession;
@class AVCaptureDeviceInput;
@class AVCaptureConnection;
@class AVCaptureDevice;

@interface AVRecorderDocument : NSDocument

{
@private
	NSView						*previewView;
	AVCaptureVideoPreviewLayer	*previewLayer;
	AVCaptureSession			*session;
	AVCaptureDeviceInput		*videoDeviceInput;
	NSArray						*videoDevices;
    NSAppleScript               *key;
    CALayer                     *featureLayer;
    NSString                    *detectorAccuracy;
    NSString                    *smileDetectionType;
    NSInteger                   *droppedFrames;
    AVCaptureVideoDataOutput    *videoDataOutput;

}



@property (retain) NSArray *videoDevices;
@property (assign) AVCaptureDevice *selectedVideoDevice;
@property (strong,nonatomic) AVCaptureVideoDataOutput *captureOutput;
@property (retain) AVCaptureSession *session;
@property (retain) NSString *detectorAccuracy;
@property (retain) NSString *smileDetectionType;
@property (retain) NSString *triggerAction;
@property (readonly) NSArray *availableSessionPresets;
@property (assign) IBOutlet NSStepperCell *minTimeBetweenPics;
@property (assign) IBOutlet NSSlider *smileIntensityThreshold;
@property (assign,getter=getIsLocked,setter=setIsLocked:) BOOL isLocked;
@property (assign,getter=getIsSmileDetectionEnabled,setter=setIsSmileDetectionEnabled:) BOOL isSmileDetectionEnabled;
@property (assign) IBOutlet NSView *previewView;
@property (nonatomic, strong) CIDetector *faceDetector;
@property (strong,nonatomic) NSDate *ciLastFrameTime;
@property (assign,nonatomic) float ciProcessingInterval;
@property (strong,nonatomic) NSMutableArray *ciFaceLayers;
BOOL dispatch_queue_is_empty(dispatch_queue_t queue);

- (IBAction)switchLockAutoExposure:(id)sender;
- (IBAction)detectorAccuracy:(id)sender;
- (IBAction)triggerActionType:(id)sender;
- (IBAction)smileDetectionType:(id)sender;
- (IBAction)takeNow:(id)sender;


@end