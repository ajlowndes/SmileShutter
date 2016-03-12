/*
 Todo:
 - fix the smile cascade xml file path - currently an absolute path rather than reference to something within the group.
 - once the smile sizes are learned, a close face will gather a larger smile size than a further away face. Fix this by scaling to the largest smile size so far found.
 - add in gphoto2 as a third option for the trigger type
 - add in a custom option for the trigger type - let the user choose
 
 - some sort of sorta-crash to be replicated and fixed, possibly by forcing a refresh of the device selection. details:
        [22:21:32.507] vtDecompressionDuctDecodeSingleFrame signalled err=-12909 (err) (VTVideoDecoderDecodeFrame returned error) at /SourceCache/CoreMedia_frameworks/CoreMedia-1562.235/Sources/VideoToolbox/VTDecompressionSession.c line 3241
        [2015-06-18 22:21:32.509 SmileShutter[22221:6740655] Dropped a source frame just now, total: 8
 */



#import "AVRecorderDocument.h"
#include <opencv2/opencv.hpp>

@interface AVRecorderDocument () <AVCaptureVideoDataOutputSampleBufferDelegate>

// Properies for internal use
@property (retain) AVCaptureDeviceInput *videoDeviceInput;
@property (retain) AVCaptureVideoPreviewLayer *previewLayer;
@property (retain) CALayer *featureLayer;
//@property (nonatomic, strong) NSImage *borderImage;
@property CFTimeInterval beginTime;
@property (retain) AVCaptureVideoDataOutput *videoDataOutput;
@property (retain, nonatomic) CIContext *context;

// Methods for internal use
- (void)refreshDevices;

@end

@implementation AVRecorderDocument

@synthesize videoDeviceInput;
@synthesize videoDevices;
@synthesize session;
@synthesize isLocked;
@synthesize isSmileDetectionEnabled;
@synthesize minTimeBetweenPics;
@synthesize detectorAccuracy;
@synthesize smileDetectionType;
@synthesize triggerAction;
@synthesize previewView;
@synthesize previewLayer;
@synthesize featureLayer;
@synthesize smileIntensityThreshold;
@synthesize videoDataOutput;

//cv::String smile_cascade_name = "/Users/ajlowndes/Downloads/SmileShutterData 3-5-2015/SmileShutter_1_2/AVRecorder/en.lproj/haarcascade_smile.xml";
cv::String smile_cascade_name = "/Users/ajlowndes/Downloads/SmileShutterData 3-5-2015/SmileShutter_1_6/AVRecorder/en.lproj/smiled_05.xml";  //need to fix this so it uses the current directory properly...
cv::CascadeClassifier smileCascade;
float smileIntensityZeroOne;
CvMemStorage storage;
long droppedFrames;
dispatch_queue_t captureOutputQueue;
CALayer *mouthLayer;
CGRect faceRect;
BOOL queueEnabled;
dispatch_queue_t ioQueue;



- (id)init
{
	self = [super init];
	if (self)
    {
		
		// Select devices if any exist
		AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
		if (videoDevice)
        {
			[self setSelectedVideoDevice:videoDevice];
		} else
        {
			[self setSelectedVideoDevice:[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeMuxed]];
		}
        NSError *error = nil;
        // Add an input
        videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
        
        // (1) Instantiate a new video data output object
        videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
        //videoDataOutput.videoSettings = @{ (NSString *) kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };
        
        // discard if the data output queue is blocked (as we process the still image
        videoDataOutput.alwaysDiscardsLateVideoFrames = YES;
        
        // (2) The sample buffer delegate requires a serial dispatch queue
        captureOutputQueue = dispatch_queue_create("CaptureOutputQueue", DISPATCH_QUEUE_SERIAL);

        [videoDataOutput setSampleBufferDelegate:self queue:captureOutputQueue];
//        dispatch_release(captureOutputQueue);
        
        // (3) Define the pixel format for the video data output
        NSString * pixelKey = (NSString*)kCVPixelBufferPixelFormatTypeKey;
        NSNumber * value = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA];
        
//        NSDictionary * settings = @{pixelKey:value};
        NSDictionary* settings = [NSDictionary dictionaryWithObject:value forKey:pixelKey];
        [videoDataOutput setVideoSettings:settings];
        
        // Create a capture session
        session = [[AVCaptureSession alloc] init];
        
        [self.session addInput:self.videoDeviceInput];
        
        // (4) Configure the output port on the captureSession property
        if ( [self.session canAddOutput:videoDataOutput] ) {
            [session addOutput:videoDataOutput];};
        
        // Set a session preset (resolution)
        self.session.sessionPreset = AVCaptureSessionPreset640x480;
        
        self.detectorAccuracy = @"CIDetectorAccuracyLow";
        self.triggerAction = @"IRsound";
        self.smileDetectionType = @"OFF";
        
        // Initialise the Face Detector
        [self initFaceDetector];
        
        // and the OpenCV smile Cascade
        if( !smileCascade.load( smile_cascade_name) ){ printf("--(!)Error loading smiles cascade\n"); };
        
        // Start the session
//        [[self session] startRunning];
        if (!session.isRunning) {[[self session] startRunning];};
        
        
        // Initial refresh of device list
        [self refreshDevices];
        
    }
	return self;
}




// Attempt at capturing whenever the AVCaptureOutput is dropping frames.
- (void)captureOutput:(AVCaptureOutput *)captureOutput
  didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    droppedFrames ++;
    NSLog(@"Dropped a source frame just now, total: %@", @((long)( droppedFrames)));
}



// Implement the Sample Buffer Delegate Method
- (void) captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
//- (void) captureOutput:videoDataOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    
    // (5) Convert CMSampleBufferRef to a CI Image
    CVImageBufferRef cvFrameBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate);
    if(attachments)
    {
        CFRelease(attachments);
    }
    NSString * pixelKey = (NSString*)kCVPixelBufferPixelFormatTypeKey;
    // NSNumber * value = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA]; //ORIGINAL 1/6/2015
    NSNumber * value = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_16Gray];
    
    NSDictionary * settings = @{pixelKey:value};
    
    //CIImage *ciFrameImage = [CIImage imageWithCVImageBuffer:cvFrameBuffer options:(NSDictionary *)settings]; //ORIG 15-5-2015
    CIImage *ciFrameImage = [CIImage imageWithCVImageBuffer:cvFrameBuffer options:settings];
    
    NSArray *featureArray = nil;
    
    if ([self.smileDetectionType  isEqual: @"OFF"])
    {
        featureArray = [self.faceDetector featuresInImage:ciFrameImage options:nil];
    }
    else if ([self.smileDetectionType isEqual: @"CIDetector"])
    {
        featureArray = [self.faceDetector featuresInImage:ciFrameImage options:@{CIDetectorSmile: @YES, CIDetectorMinFeatureSize:smileIntensityThreshold}]; //Originally CIDetectorMinFeatureSize was 0.9.. but it makes no difference.
    }
    else if ([self.smileDetectionType isEqual: @"OpenCV"])
    {
        featureArray = [self.faceDetector featuresInImage:ciFrameImage options:nil];
    }
    else if ([self.smileDetectionType isEqual: @"Ofx"])
    {
        featureArray = [self.faceDetector featuresInImage:ciFrameImage options:nil];
    }
    
    CMFormatDescriptionRef fdesc = CMSampleBufferGetFormatDescription(sampleBuffer);
    CGRect cleanAperture = CMVideoFormatDescriptionGetCleanAperture(fdesc, false /*originIsTopLeft == false*/);

    
    ioQueue = dispatch_queue_create("FeatureDetectorQueue", NULL);
    int cpuCount = (int)[[NSProcessInfo processInfo] processorCount];
    dispatch_semaphore_t jobSemaphore = dispatch_semaphore_create(cpuCount);
    dispatch_group_t group = dispatch_group_create();
    dispatch_semaphore_wait(jobSemaphore, DISPATCH_TIME_FOREVER);
    if (queueEnabled){
        dispatch_group_async(group, ioQueue, (^{
            [self drawFaces:featureArray forVideoBox:cleanAperture refImage:ciFrameImage];
            if (dispatch_queue_is_empty(ioQueue)) {
                dispatch_semaphore_signal(jobSemaphore);
            };
        }));
    }
}

//Checker to see if the queue is emtpy so the next frame can be sent to be processed.
BOOL dispatch_queue_is_empty(dispatch_queue_t queue)
    {
        dispatch_group_t group = dispatch_group_create();
        
        dispatch_group_enter(group);
        dispatch_async(queue, ^{
            dispatch_group_leave(group);
        });
        
        int64_t maxWaitTime = 0.00000005 * NSEC_PER_SEC;
        BOOL isReady = dispatch_group_wait(group, maxWaitTime) == 0;
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
            dispatch_release(group);
        });
        
        return isReady;
    }

// called asynchronously as the capture output is capturing sample buffers, this method asks the face and smile detectors
// for any detected features and for each draw the black border(s) in a layer
- (void)drawFaces:(NSArray *)featureArray
      forVideoBox:(CGRect)cleanAperture refImage:ciFrameImage
{
    
    NSArray *sublayers = [NSArray arrayWithArray:[self.previewLayer sublayers]];
    NSInteger sublayersCount = [sublayers count], currentSublayer = 0;
    NSInteger featuresCount = [featureArray count], currentFeature = 0;
    
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    
    // hide all the face layers
    for ( CALayer *layer in sublayers )
    {
        if ( [[layer name] isEqualToString:@"FaceLayer"] )
            [layer setHidden:YES];
        if ( [[layer name] isEqualToString:@"MouthLayer"] )
            [layer setHidden:YES];
        if ( [[layer name] isEqualToString:@"SmileMeterBGLayer"] )
            [layer setHidden:YES];
        if ( [[layer name] isEqualToString:@"SmileMeterLayer"] )
            [layer setHidden:YES];
        if ( [[layer name] isEqualToString:@"SmileIntensityThresholdMarkerLayer"] )
            [layer setHidden:YES];
    }
    
    if ( featuresCount == 0 ) {
        [CATransaction commit];
        return; // early bail.
    }
    
    CGRect previewBox = NSRectToCGRect([self.previewView bounds]);
    
    for ( CIFaceFeature *faceFeature in featureArray)
    {
        featureLayer = nil;
        if ([faceFeature.type isEqualToString:CIFeatureTypeFace])
        {
            //NSLog(@"tracking id: %@", @(faceFeature.trackingID));
            faceRect = faceFeature.bounds;
            
            CGFloat widthScaleBy = previewBox.size.width / cleanAperture.size.width;
            CGFloat heightScaleBy = previewBox.size.height / cleanAperture.size.height;
            faceRect.size.width *= widthScaleBy;
            faceRect.size.height *= heightScaleBy;
            faceRect.origin.x *= widthScaleBy;
            faceRect.origin.y *= heightScaleBy;
            
            // re-use an existing layer if possible
            while ( !featureLayer && (currentSublayer < sublayersCount) )
            {
                CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
                if ( [[currentLayer name] isEqualToString:@"FaceLayer"] )
                {
                    featureLayer = currentLayer;
                    [currentLayer setHidden:NO];
                }
            }
            // create a new layer if necessary
            if ( !featureLayer )
            {
                featureLayer = [[CALayer alloc]init];
                featureLayer.contentsRect = faceRect;
                [featureLayer setName:@"FaceLayer"];
                [self.previewLayer addSublayer:featureLayer];
                [featureLayer release];     //Wait...what?
            }
            
            // Fill featureLayer with the faces and any detected features
            [featureLayer setFrame:faceRect];
            [featureLayer setBorderWidth:2.0f];
            [featureLayer setBorderColor:(CGColorCreateGenericRGB(1.0, 1.0, 1.0, 0.5))];
            [featureLayer setBackgroundColor:(CGColorCreateGenericRGB(1.0, 1.0, 1.0, 0.0))];
            
            if ([self.smileDetectionType  isNotEqualTo: @"OFF"])
            {
                if (faceFeature.hasMouthPosition)
                {
                    
                    // Draw a box around the mouth.
                    CGPoint mouthPoint = faceFeature.mouthPosition;
                    double   mouthRectHeight = (faceRect.size.height/5.0);  //height of the rectangle to draw
                    double   mouthRectWidth = (faceRect.size.width/3.0);  //width of the rectangle to draw
                    CGRect mouthRect = NSMakeRect(mouthPoint.x * widthScaleBy - mouthRectWidth,
                                                  mouthPoint.y * heightScaleBy - mouthRectHeight,
                                                  2.0 * mouthRectWidth,
                                                  2.0 * mouthRectHeight);
                    mouthLayer = [CALayer layer];
                    mouthLayer.borderWidth = 2.0f;
                    mouthLayer.borderColor =(CGColorCreateGenericRGB(1.0,1.0,1.0,0.5));
                    mouthLayer.backgroundColor = (CGColorCreateGenericRGB(1.0,1.0,1.0,0.0));
                    mouthLayer.frame = mouthRect;
                    [mouthLayer setName:@"MouthLayer"];
                    
                    //Draw the Smile Intensity Meter Background on the right side of the face
                    double smileMeterBGHeight = (faceRect.size.height * 0.9);
                    double smileMeterBGWidth = (faceRect.size.width * 0.05);
                    CGRect smileMeterBGRect = NSMakeRect(faceRect.origin.x +(faceRect.size.width * 0.9),
                                                         faceRect.origin.y + (faceRect.size.height * 0.05) ,
                                                         smileMeterBGWidth,
                                                         smileMeterBGHeight);
                    CALayer *smileMeterBGLayer = [CALayer layer];
                    smileMeterBGLayer.borderWidth = 2.0f;
                    smileMeterBGLayer.borderColor =(CGColorCreateGenericRGB(1.0,1.0,1.0,0.5));
                    smileMeterBGLayer.backgroundColor = (CGColorCreateGenericRGB(0.0,0.0,0.0,1.0));
                    smileMeterBGLayer.frame = smileMeterBGRect;
                    [smileMeterBGLayer setName:@"SmileMeterBGLayer"];
                    
                    //Draw the Smile Intensity Theshold Marker on top of smileMeterBGLayer
                    CGRect smileIntensityThresholdMarkerRect = NSMakeRect(faceRect.origin.x + (faceRect.size.width * 0.9) + 1.0f,
                                                                          faceRect.origin.y + (faceRect.size.height * 0.05) + (faceRect.size.height * 0.95 *smileIntensityThreshold.floatValue),
                                                                          (smileMeterBGWidth - 2.0f),
                                                                          1.0f);
                    CALayer *smileIntensityThresholdMarkerLayer = [CALayer layer];
                    smileIntensityThresholdMarkerLayer.borderWidth = 1.0f;
                    smileIntensityThresholdMarkerLayer.borderColor =(CGColorCreateGenericRGB(1.0,0.0,0.0,1.0));
                    smileIntensityThresholdMarkerLayer.frame = smileIntensityThresholdMarkerRect;
                    [smileIntensityThresholdMarkerLayer setName:@"SmileIntensityThresholdMarkerLayer"];
                    
                    
                    smileIntensityZeroOne = 0;
                    
                    //If CIDetector is used, it is implied here, otherwise no smiles are detected.
                    if (faceFeature.hasSmile)
                    {
                        smileIntensityZeroOne = 1;
                        [self smileEvent];
                    }
                    
                    if ([self.smileDetectionType isEqual: @"OpenCV"])
                    {
                        [self OpenCVdetectSmilesIn:faceFeature
                                        usingImage:ciFrameImage];
                        if (smileIntensityZeroOne > smileIntensityThreshold.floatValue){
                            [self smileEvent];
                            //NSLog(@"OpenCV reported smile level %.2f", ((float)(smileIntensityZeroOne)));
                        }
                    }
                    
                    if ([self.smileDetectionType isEqual: @"Ofx"])
                    {
                        [self OfxDetectSmilesIn:faceFeature
                                     usingImage:ciFrameImage];
                        if (smileIntensityZeroOne > smileIntensityThreshold.floatValue){
                            [self smileEvent];
                            //NSLog(@"Ofx reported smile level %.2f", ((float)(smileIntensityZeroOne)));
                        }
                    }
                    
                    //Draw the Smile Intensity Meter on top of smileMeterBGLayer
                    double smileMeterHeight = (faceRect.size.height * 0.9 * smileIntensityZeroOne) - 2.0f;
                    double smileMeterWidth = smileMeterBGWidth -2.0f;
                    if (smileMeterWidth < 2.0f) {smileMeterWidth = 2.0f;};
                    CGRect smileMeterRect = NSMakeRect(faceRect.origin.x + (faceRect.size.width * 0.9) + 1.0f ,
                                                         faceRect.origin.y + (faceRect.size.height * 0.05) + 1.0f ,
                                                         smileMeterWidth,
                                                         smileMeterHeight);
                    CALayer *smileMeterLayer = [CALayer layer];
                    smileMeterLayer.borderWidth = 0.0f;
                    smileMeterLayer.backgroundColor = (CGColorCreateGenericRGB(0.0,1.0,0.0,1.0));
                    smileMeterLayer.frame = smileMeterRect;
                    [smileMeterLayer setName:@"SmileMeterLayer"];
                    
                    
                    [self.previewLayer insertSublayer:mouthLayer above:featureLayer];
                    [self.previewLayer insertSublayer:smileMeterBGLayer above:mouthLayer];
                    [self.previewLayer insertSublayer:smileMeterLayer above:smileMeterBGLayer];
                    [self.previewLayer insertSublayer:smileIntensityThresholdMarkerLayer above:smileMeterLayer];
                    
                }
            }

        }
        currentFeature++;
    }
    [CATransaction commit];
    
}


// If OpenCV is used for the smile size detection...
- (void)OpenCVdetectSmilesIn:(CIFaceFeature *)faceFeature usingImage:ciFrameImage
{
    CGRect lowerFaceRectFull = faceFeature.bounds;
    lowerFaceRectFull.size.height *=0.5;
    CIImage *lowerFaceImageFull = [ciFrameImage imageByCroppingToRect:lowerFaceRectFull];
    
    // Create the context and instruct CoreImage to draw the output image recipe into a CGImage
    if( self.context == nil ) {
        self.context = [CIContext contextWithCGContext:nil options: nil];
    }
    CGImageRef lowerFaceImageFullCG = [_context createCGImage:lowerFaceImageFull fromRect:lowerFaceRectFull];
    
    cv::Mat frame_gray;
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(lowerFaceImageFullCG);
    CGFloat cols = lowerFaceRectFull.size.width;
    CGFloat rows = lowerFaceRectFull.size.height;
    cv::Mat cvMat(rows, cols, CV_8UC4); // 8 bits per component, 4 channels

    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,                 // Pointer to backing data
                                                    cols,                      // Width of bitmap
                                                    rows,                     // Height of bitmap
                                                    8,                          // Bits per component
                                                    cvMat.step[0],              // Bytes per row
                                                    colorSpace,                 // Colorspace
                                                    kCGImageAlphaNoneSkipLast |
                                                    kCGBitmapByteOrderDefault); // Bitmap info flags

    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), lowerFaceImageFullCG);
    CGImageRelease(lowerFaceImageFullCG);
    CGContextRelease(contextRef);
    
    cvtColor( cvMat, frame_gray, CV_BGR2GRAY );
    equalizeHist( frame_gray, frame_gray );
    
    //    NSImage *lowerFaceImageFullGrey = [NSImage imageWithCVMat:frame_gray];

    std::vector<cv::Rect> smileObjects;
    smileCascade.detectMultiScale( frame_gray, smileObjects, 1.1, 0, 0 | CV_HAAR_SCALE_IMAGE, cv::Size(30, 30) );
    
    //if a smile was found
    if ( smileObjects.size() > 0 ) {
        
        //calculate the smile intensity
        const int smile_neighbors = (int) smileObjects.size();
        static int max_neighbors = -1;
        static int min_neighbors = -1;
        if ( min_neighbors == -1) min_neighbors = smile_neighbors;
        max_neighbors = MAX(max_neighbors, smile_neighbors);
        smileIntensityZeroOne = ((float)smile_neighbors - min_neighbors) / (max_neighbors - min_neighbors + 1);
        if (smileIntensityZeroOne < 0) {smileIntensityZeroOne = 0;};
        
    }
}

// If Openframeworks is used for the smile detection...
- (void)OfxDetectSmilesIn:(CIFaceFeature *)faceFeature usingImage:ciFrameImage
{
    CGRect lowerFaceRectFull = faceFeature.bounds;
    lowerFaceRectFull.size.height *=0.5;
    
    CIImage *lowerFaceImageFull = [ciFrameImage imageByCroppingToRect:lowerFaceRectFull];
    
    // Create the context and instruct CoreImage to draw the output image recipe into a CGImage
    if( self.context == nil ) {
        self.context = [CIContext contextWithCGContext:nil options: nil];
    }
    CGImageRef lowerFaceImageFullCG = [_context createCGImage:lowerFaceImageFull fromRect:lowerFaceRectFull];
    
    cv::Mat frame_gray;
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(lowerFaceImageFullCG);
    CGFloat cols = lowerFaceRectFull.size.width;
    CGFloat rows = lowerFaceRectFull.size.height;
    cv::Mat cvMat(rows, cols, CV_8UC4); // 8 bits per component, 4 channels
    
    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,                 // Pointer to backing data
                                                    cols,                      // Width of bitmap
                                                    rows,                     // Height of bitmap
                                                    8,                          // Bits per component
                                                    cvMat.step[0],              // Bytes per row
                                                    colorSpace,                 // Colorspace
                                                    kCGImageAlphaNoneSkipLast |
                                                    kCGBitmapByteOrderDefault); // Bitmap info flags
    
    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), lowerFaceImageFullCG);
    CGImageRelease(lowerFaceImageFullCG);
    CGContextRelease(contextRef);
    
    cvtColor( cvMat, frame_gray, CV_BGR2GRAY );
    equalizeHist( frame_gray, frame_gray );
    
    //    NSImage *lowerFaceImageFullGrey = [NSImage imageWithCVMat:frame_gray];
    
    float minSizeScale = .1;
    float maxSizeScale = 1;
    cv::Size minSize, maxSize;
    float averageSide = (frame_gray.rows + frame_gray.cols) / 2;
    if(minSizeScale > 0) {
        int side = minSizeScale * averageSide;
        minSize = cv::Size(side, side);
    }
    if(maxSizeScale < 1) {
        int side = maxSizeScale * averageSide;
        maxSize = cv::Size(side, side);
    }
    
    std::vector<cv::Rect> smileObjects;
    smileCascade.detectMultiScale( frame_gray, smileObjects, 1.1, 0, 0 | CV_HAAR_SCALE_IMAGE, minSize, maxSize );
    
    float rescale = 0.5;
    for(int i = 0; i < smileObjects.size(); i++) {
        cv::Rect& rect = smileObjects[i];
        rect.width /= rescale, rect.height /= rescale;
        rect.x /= rescale, rect.y /= rescale;
    }
    
    //if a smile was found
    if ( smileObjects.size() > 0 ) {
        
        //calculate the smile intensity
        const int smile_neighbors = (int) smileObjects.size();
        static int max_neighbors = -1;
        static int min_neighbors = -1;
        if ( min_neighbors == -1) min_neighbors = smile_neighbors;
        max_neighbors = MAX(max_neighbors, smile_neighbors);
        smileIntensityZeroOne = ((float)smile_neighbors - min_neighbors) / (max_neighbors - min_neighbors + 1);
        if (smileIntensityZeroOne < 0) {smileIntensityZeroOne = 0;};
    }
    
}


- (NSString *)windowNibName
{
	return @"AVRecorderDocument";
}


- (void)windowControllerDidLoadNib:(NSWindowController *) aController
{
	[super windowControllerDidLoadNib:aController];
    
	
    [previewView  setWantsLayer:YES];
    [previewView setLayerUsesCoreImageFilters:YES]; //What's this for again?
    
    // Attach preview to session
    CALayer *rootLayer = previewView.layer;
    [rootLayer setMasksToBounds:YES]; //aaron added
    self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
	[self.previewLayer setBackgroundColor:CGColorGetConstantColor(kCGColorBlack)];
    [self.previewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
	[self.previewLayer setFrame:[rootLayer bounds]];
	[self.previewLayer setAutoresizingMask:kCALayerWidthSizable | kCALayerHeightSizable];
    [self.previewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
	[rootLayer addSublayer:previewLayer];
   	[rootLayer release];

	
}


- (void)didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void  *)contextInfo
{
	// Do nothing
}

/********** Manage the CIDetectorAccuracy **********/

- (IBAction)detectorAccuracy:(id)sender
{
    // change the CIDetectorAccuracy (default will be Low)
    [session stopRunning];
    switch ([[sender selectedCell] tag]) {
        case 0:
            self.detectorAccuracy = @"CIDetectorAccuracyLow";
            break;
        case 1:
            self.detectorAccuracy = @"CIDetectorAccuracyHigh";
            break;
    }
    if (self.faceDetector)
        [CIDetector release];
    [self initFaceDetector];
}

- (void)initFaceDetector {
    
    self.faceDetector = [CIDetector detectorOfType:CIDetectorTypeFace
                                           context:nil
                                           options:@{ CIDetectorAccuracy : self.detectorAccuracy,
                                                      CIDetectorTracking : @YES
                                                      }];
    [session startRunning];
}

/********** Manage the Smile Detection Type **********/
- (IBAction)smileDetectionType:(id)sender
{
    // change the smile Detection Type (default will be OFF)
    switch ([[sender selectedCell] tag]) {
        case 0:
            self.smileDetectionType = @"OFF";
            self.isSmileDetectionEnabled = NO;
            break;
        case 1:
            self.smileDetectionType = @"CIDetector";
            self.isSmileDetectionEnabled = YES;
            break;
        case 2:
            self.smileDetectionType = @"OpenCV";
            self.isSmileDetectionEnabled = YES;
            break;
        case 3:
            self.smileDetectionType = @"Ofx";
            self.isSmileDetectionEnabled = YES;
            break;
    }
}

/********** Manage the Smile Detection Event by making the mouthLayer object green and sending the  **********/
- (void)smileEvent {
    
    mouthLayer.borderColor = (CGColorCreateGenericRGB(0.0, 1.0, 0.0, 1.0));
    
    CFTimeInterval currentTime = CACurrentMediaTime();
    if ((currentTime - _beginTime) > minTimeBetweenPics.doubleValue)
    {
        [mouthLayer setBackgroundColor:(CGColorCreateGenericRGB(0.0, 0.0, 0.0, 1.0))];
        [self sendTrigger];
        _beginTime = currentTime;
        //NSLog(@"Triggered");
    }
}


/**********  Handler for the "Take Pic Now" button  **********/
- (IBAction)takeNow:(id)sender
{
    [featureLayer setBackgroundColor:(CGColorCreateGenericRGB(0.0, 0.0, 0.0, 1.0))];
    CFTimeInterval currentTime = CACurrentMediaTime();
    if ((currentTime - _beginTime) > minTimeBetweenPics.doubleValue)
    {
        [self sendTrigger];
        _beginTime = currentTime;
    }
}

/********** Manage the user-defined trigger action and pass it to the System Events **********/

- (IBAction)triggerActionType:(id)sender
{
    // change the TriggerType (default will be Low)
    switch ([[sender selectedCell] tag]) {
        case 0:
            self.triggerAction = @"keys";
            break;
        case 1:
            self.triggerAction = @"IRsound";
            break;
    }
}

- (void) sendTrigger
{
    if ([triggerAction  isEqual: @"keys"]) [self sendKeys];
    if ([triggerAction  isEqual: @"IRsound"]) [self sendIRSound];
}

- (void) sendIRSound
{
    static NSSound *sonyTriggerSound = nil;
    sonyTriggerSound = [NSSound soundNamed:@"sonynexshutterrelease"];
    [sonyTriggerSound play];
}

- (void) sendKeys
{
    [[self class] runScript:@"tell application \"System Events\" to keystroke \"p\" using {control down, option down, command down} "];
}

//To Do: add a third option here - use gphoto2 to take and download an image.

/********** Manage the applescript **********/

+(void)runScript:(NSString*)scriptText
{
    NSDictionary *error = nil;
    NSAppleEventDescriptor *appleEventDescriptor;
    NSAppleScript *appleScript;
    appleScript = [[NSAppleScript alloc] initWithSource:scriptText];
    appleEventDescriptor = [appleScript executeAndReturnError:&error];
}

/********** Manage video sources **********/

- (void)refreshDevices
{
    [self setVideoDevices:[[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] arrayByAddingObjectsFromArray:[AVCaptureDevice devicesWithMediaType:AVMediaTypeMuxed]]];
    
    [[self session] beginConfiguration];
    
    if (![[self videoDevices] containsObject:[self selectedVideoDevice]])
        [self setSelectedVideoDevice:nil];
    
    [[self session] commitConfiguration];
}

- (AVCaptureDevice *)selectedVideoDevice
{
    return [videoDeviceInput device];
}

// Change the video source on demand
- (void)setSelectedVideoDevice:(AVCaptureDevice *)selectedVideoDevice
{
    NSLog(@"device changed to \"%@\"", selectedVideoDevice.localizedName);
    queueEnabled = false; //to stop the queue continuing to load frames
    [self unlockDevice:selectedVideoDevice];
    if (videoDataOutput)
    {
        [session removeOutput:videoDataOutput];
    }
    [videoDeviceInput retain];
    
    [[self session] beginConfiguration];
    // Remove the old device input from the session
    if (videoDeviceInput)
    {
        [session removeInput:videoDeviceInput];
        [self setVideoDeviceInput:nil];
    }
    if (selectedVideoDevice)
    {
        NSError *error = nil;
        // Create a device input for the device and add it to the session
        AVCaptureDeviceInput *newVideoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:selectedVideoDevice error:&error];
        if (newVideoDeviceInput == nil)
        {
            dispatch_async(dispatch_get_main_queue(), ^(void)
                           {
                               [self presentError:error];
                           });
        } else
        {
            if (![selectedVideoDevice supportsAVCaptureSessionPreset:[session sessionPreset]])
                [session setSessionPreset:AVCaptureSessionPreset640x480];
            
            [session addInput:newVideoDeviceInput];
            [self setVideoDeviceInput:newVideoDeviceInput];
        }
    }

    [[self session] commitConfiguration];

    if ([session canAddOutput:videoDataOutput])
    {
        [session addOutput:videoDataOutput];
        [videoDataOutput setSampleBufferDelegate:self queue:captureOutputQueue];
    };
    queueEnabled = true;
}

/********** Manage exposure locking/unlocking **********/

- (IBAction)switchLockAutoExposure:(id)sender
{
    self.isLocked=!self.getIsLocked;
	[self setLockExposure:(BOOL)self.getIsLocked];
}
 
- (void)setLockExposure:(BOOL)locked
{
    AVCaptureDevice *device = [self selectedVideoDevice];
    if(locked) {
        if ([device isExposureModeSupported:AVCaptureExposureModeLocked]) {
            NSError *error = nil;
            if ([device lockForConfiguration:&error]) {
                device.exposureMode = AVCaptureExposureModeLocked;
                NSLog(@"Auto-exposure is now locked");
            }
            else {
                NSLog(@"%@ couldn't be locked", device.localizedName);
            }
        } else {
            NSLog(@"%@ does not support Auto-Exposure locking", device.localizedName);
        }
        
    } else {
        if (device.exposureMode == AVCaptureExposureModeLocked) {
            [self unlockDevice:device];
        }
	}
}

-(void)unlockDevice:(AVCaptureDevice *)device
{
    NSError *error = nil;
    if ([device lockForConfiguration:&error]) {
        //[device lockForConfiguration];
        device.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
        [device unlockForConfiguration];
        NSLog(@"%@ successfully unlocked", device.localizedName);
    }
    else {
        NSLog(@"%@ can't be unlocked", device.localizedName);
        // Respond to the failure as appropriate.
    }
}

- (void)unlockAllDevices
{
    NSLog(@"Unlocking all devices...");
    NSUInteger i = [videoDevices count]; while ( i-- ) {
        //AVCaptureDevice *device = [videoDevices objectAtIndex:i];
        [self unlockDevice:[videoDevices objectAtIndex:i]];
    }
}


/********** End the program **********/

- (void)windowWillClose:(NSNotification *)notification
{
    [self unlockAllDevices];
	[[self session] stopRunning];
}

- (void)dealloc
{
	[videoDevices release];
	[session release];
	[previewLayer release];
//	[videoDeviceInput release];
    [CIDetector release];
    //(Aaron): should probably add the rest of the variables here as well...
	
	[super dealloc];
}

@end
