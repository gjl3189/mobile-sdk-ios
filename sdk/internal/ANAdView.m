/*   Copyright 2013 APPNEXUS INC
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "ANAdView.h"

//#import "ANAdFetcher.h"     //FIX UT -- deprecated TOSS
#import "ANUniversalAdFetcher.h"
#import "ANGlobal.h"
#import "ANLogging.h"
#import "ANAdServerResponse.h"

#import "UIView+ANCategory.h"
#import "UIWebView+ANCategory.h"

#import "ANBannerAdView.h"



#define  DEFAULT_PUBLIC_SERVICE_ANNOUNCEMENT  NO




@interface ANAdView () <ANAdFetcherDelegate, ANUniversalAdFetcherDelegate, ANAdViewInternalDelegate>

@property (nonatomic, readwrite, weak)    id<ANAdDelegate>        delegate;
@property (nonatomic, readwrite, weak)    id<ANAppEventDelegate>  appEventDelegate;

@property (nonatomic, readwrite, strong)  NSMutableDictionary<NSString *, NSArray<NSString *> *>  *customKeywordsMap;

@property (nonatomic, readwrite, strong)   id  adObjectResponse;

@end



@implementation ANAdView

// ANAdProtocol properties.
//
@synthesize  placementId                            = __placementId;
@synthesize  memberId                               = __memberId;
@synthesize  inventoryCode                          = __invCode;
@synthesize  opensInNativeBrowser                   = __opensInNativeBrowser;
@synthesize  shouldServePublicServiceAnnouncements  = __shouldServePublicServiceAnnouncements;
@synthesize  location                               = __location;
@synthesize  zipcode                                = __zipcode;
@synthesize  reserve                                = __reserve;
@synthesize  age                                    = __age;
@synthesize  gender                                 = __gender;
@synthesize  customKeywords                         = __customKeywords;
@synthesize  customKeywordsMap                      = __customKeywordsMap;
@synthesize  landingPageLoadsInBackground           = __landingPageLoadsInBackground;
@synthesize  adSize                                 = __adSize;
@synthesize  allowedAdSizes                         = __allowedAdSizes;



#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    
    if (self != nil) {
        [self initialize];
    }
    
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    [self initialize];
}

- (void)initialize {
    self.clipsToBounds = YES;

    self.universalAdFetcher = [[ANUniversalAdFetcher alloc] initWithDelegate:self];

    __shouldServePublicServiceAnnouncements  = DEFAULT_PUBLIC_SERVICE_ANNOUNCEMENT;
    __location                               = nil;
    __reserve                                = 0.0f;
    __customKeywords                         = [[NSMutableDictionary alloc] init];
    __customKeywordsMap                      = [[NSMutableDictionary alloc] init];
    __landingPageLoadsInBackground           = YES;

    _impressionUrlsHaveBeenFired = NO;
}

- (void)dealloc
{
ANLogMark();
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [self.universalAdFetcher stopAdLoad];
}


- (void)loadAd
{
ANLogMark();
    BOOL  placementIdValid    = [self.placementId length] >= 1;
    BOOL  inventoryCodeValid  = ([self memberId] >=1 ) && [self inventoryCode];

    if (!placementIdValid && !inventoryCodeValid) {
        NSString      *errorString  = ANErrorString(@"no_placement_id");
        NSDictionary  *errorInfo    = @{NSLocalizedDescriptionKey: errorString};
        NSError       *error        = [NSError errorWithDomain:AN_ERROR_DOMAIN code:ANAdResponseInvalidRequest userInfo:errorInfo];

        ANLogError(@"%@", errorString);
        [self adRequestFailedWithError:error];
        return;
    }

    [self.universalAdFetcher stopAdLoad];
    [self.universalAdFetcher requestAd];

    if (! self.universalAdFetcher)  {
        ANLogError(@"FAILED TO FETCH ad via UT.");
    }
}


    /* FIX adapt to UT
- (void)loadAdFromHtml:(NSString *)html
                 width:(int)width height:(int)height {
                                                    //FIX UT iupdfate?
    ANAdServerResponse *response = [[ANAdServerResponse alloc] initWithContent:html
                                                                         width:width
                                                                        height:height];
    [self.adFetcher processAdResponse:response];
}
        */




#pragma mark - Support for subclasses.

- (void) fireImpressionUrls
{
ANLogMark();
    if (!self.adObjectResponse) {
        ANLogWarn(@"adObjectResponse is UNDEFINED.");
                //FIX -- teset me s-- should not ever be UNDEFINED...
        return;
    }


    //
    NSArray<NSString *>  *impressionUrls  = nil;

    if ([self.adObjectResponse respondsToSelector:@selector(impressionUrls)]) {
        impressionUrls = [self.adObjectResponse performSelector:@selector(impressionUrls)];
                    //FIX -- test me
    }

    if (!impressionUrls || self.impressionUrlsHaveBeenFired) {
        return;
    }
ANLogMarkMessage(@"FIRED...");


    //
    NSString          *backgroundQueueName  = [NSString stringWithFormat:@"%s -- Fire impressionUrls.", __PRETTY_FUNCTION__];
    dispatch_queue_t   backgroundQueue      = dispatch_queue_create([backgroundQueueName cStringUsingEncoding:NSASCIIStringEncoding], NULL);

    dispatch_async(backgroundQueue, ^{
        for (NSString *urlString in impressionUrls)
        {
            ANLogMarkMessage(@"urlString=%@", urlString);   //DEBUG
            NSURLSessionDataTask  *dataTask =
                [[NSURLSession sharedSession] dataTaskWithURL: [NSURL URLWithString:urlString]
                                            completionHandler: ^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                                                ANLogMarkMessage(@"\n\tdata=%@ \n\tresponse=%@ \n\terror=%@", data, response, error);   //DEBUG
                                            }];
            [dataTask resume];
        }
    });

    self.impressionUrlsHaveBeenFired = YES;
}



#pragma mark - Setter methods

- (void)setPlacementId:(NSString *)placementId {
    placementId = ANConvertToNSString(placementId);
    if ([placementId length] < 1) {
        ANLogError(@"Could not set placementId to non-string value");
        return;
    }
    if (placementId != __placementId) {
        ANLogDebug(@"Setting placementId to %@", placementId);
        __placementId = placementId;
    }
}

- (void)setInventoryCode:(NSString *)invCode memberId:(NSInteger) memberId{
    invCode = ANConvertToNSString(invCode);
    if (invCode && invCode != __invCode) {
        ANLogDebug(@"Setting inventory code to %@", invCode);
        __invCode = invCode;
    }
    if (memberId > 0 && memberId != __memberId) {
        ANLogDebug(@"Setting member id to %d", (int) memberId);
        __memberId = memberId;
    }
}

- (void)setLocationWithLatitude:(CGFloat)latitude longitude:(CGFloat)longitude
                      timestamp:(NSDate *)timestamp horizontalAccuracy:(CGFloat)horizontalAccuracy {
    self.location = [ANLocation getLocationWithLatitude:latitude
                                              longitude:longitude
                                              timestamp:timestamp
                                     horizontalAccuracy:horizontalAccuracy];
}

- (void)setLocationWithLatitude:(CGFloat)latitude longitude:(CGFloat)longitude
                      timestamp:(NSDate *)timestamp horizontalAccuracy:(CGFloat)horizontalAccuracy
                      precision:(NSInteger)precision {
    self.location = [ANLocation getLocationWithLatitude:latitude
                                              longitude:longitude
                                              timestamp:timestamp
                                     horizontalAccuracy:horizontalAccuracy
                                              precision:precision];
}

- (void)addCustomKeywordWithKey:(NSString *)key
                          value:(NSString *)value {
    if (([key length] < 1) || !value) {
        return;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    // ANTargetingParameters still depends on this value
    [self.customKeywords setValue:value forKey:key];
#pragma clang diagnostic pop
    if(self.customKeywordsMap[key] != nil){
        NSMutableArray *valueArray = (NSMutableArray *)[self.customKeywordsMap[key] mutableCopy];
        if (![valueArray containsObject:value]) {
            [valueArray addObject:value];
        }
        self.customKeywordsMap[key] = [valueArray copy];
    } else {
        self.customKeywordsMap[key] = @[value];
    }
}

- (void)removeCustomKeywordWithKey:(NSString *)key {
    if (([key length] < 1)) {
        return;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    // ANTargetingParameters still depends on this value
    [self.customKeywords removeObjectForKey:key];
#pragma clang diagnostic pop
    [self.customKeywordsMap removeObjectForKey:key];
}

- (void)clearCustomKeywords {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [self.customKeywords removeAllObjects];
#pragma clang diagnostic pop
    [self.customKeywordsMap removeAllObjects];
}



#pragma mark - Getter methods

- (NSString *)placementId {
    ANLogDebug(@"placementId returned %@", __placementId);
    return __placementId;
}

- (NSInteger )memberId {
    ANLogDebug(@"memberId returned %d", (int)__memberId);
    return __memberId;
}

- (NSString *)inventoryCode {
    ANLogDebug(@"inventoryCode returned %@", __invCode);
    return __invCode;
}

- (ANLocation *)location {
    ANLogDebug(@"location returned %@", __location);
    return __location;
}

- (NSString *) zipcode {
    ANLogDebug(@"zipcode returned %@", __zipcode);
    return __zipcode;
}

- (BOOL)shouldServePublicServiceAnnouncements {
    ANLogDebug(@"shouldServePublicServeAnnouncements returned %d", __shouldServePublicServiceAnnouncements);
    return __shouldServePublicServiceAnnouncements;
}

- (BOOL)opensInNativeBrowser {
    ANLogDebug(@"opensInNativeBrowser returned %d", __opensInNativeBrowser);
    return __opensInNativeBrowser;
}

- (CGFloat)reserve {
    ANLogDebug(@"reserve returned %f", __reserve);
    return __reserve;
}

- (NSString *)age {
    ANLogDebug(@"age returned %@", __age);
    return __age;
}

- (ANGender)gender {
    ANLogDebug(@"gender returned %lu", (long unsigned)__gender);
    return __gender;
}

- (NSMutableDictionary *)customKeywords {
    ANLogDebug(@"customKeywords returned %@", __customKeywords);
    return __customKeywords;
}




//---------------------------------------------------------- -o--
#pragma mark - ANUniversalAdFetcherDelegate.

//--------------------- -o-
- (void)       universalAdFetcher: (ANUniversalAdFetcher *)fetcher
     didFinishRequestWithResponse: (ANAdFetcherResponse *)response
                                                        //FIX -- also test for isSuccessful?
{
ANLogMark();
    if (response.adObjectResponse) {
        self.adObjectResponse = response.adObjectResponse;
    }
}

        /* FIX toss
- (void)universalAdFetcher:(ANUniversalAdFetcher *)fetcher impressionUrls:(NSArray<NSString *> *)impressionUrls
{
    self.impressionUrls = impressionUrls;
ANLogMarkMessage(@"%@", self.impressionUrls);
}
                */



//---------------------------------------------------------- -o--
#pragma mark - ANAdViewInternalDelegate

- (void)adWasClicked {
ANLogMark();
    if ([self.delegate respondsToSelector:@selector(adWasClicked:)]) {
        [self.delegate adWasClicked:self];
    }
}

- (void)adWillPresent {
ANLogMark();
    if ([self.delegate respondsToSelector:@selector(adWillPresent:)]) {
        [self.delegate adWillPresent:self];
    }
}

- (void)adDidPresent {
ANLogMark();
    if ([self.delegate respondsToSelector:@selector(adDidPresent:)]) {
        [self.delegate adDidPresent:self];
    }
}

- (void)adWillClose {
ANLogMark();
    if ([self.delegate respondsToSelector:@selector(adWillClose:)]) {
        [self.delegate adWillClose:self];
    }
}

- (void)adDidClose {
ANLogMark();
    if ([self.delegate respondsToSelector:@selector(adDidClose:)]) {
        [self.delegate adDidClose:self];
    }
}

- (void)adWillLeaveApplication {
ANLogMark();
    if ([self.delegate respondsToSelector:@selector(adWillLeaveApplication:)]) {
        [self.delegate adWillLeaveApplication:self];
    }
}

- (void)adDidReceiveAppEvent:(NSString *)name withData:(NSString *)data {
ANLogMark();
    if ([self.appEventDelegate respondsToSelector:@selector(ad:didReceiveAppEvent:withData:)]) {
        [self.appEventDelegate ad:self didReceiveAppEvent:name withData:data];
    }
}

- (void)adDidReceiveAd
{
ANLogMark();
    if ([self.delegate respondsToSelector:@selector(adDidReceiveAd:)]) {
        [self.delegate adDidReceiveAd:self];
    }
}

- (void)adRequestFailedWithError:(NSError *)error {
ANLogMark();
    if ([self.delegate respondsToSelector:@selector(ad: requestFailedWithError:)]) {
        [self.delegate ad:self requestFailedWithError:error];
    }
}


        /* FIX toss --or-- adap[t to UT?
- (void)adInteractionDidBegin {
    ANLogDebug(@"%@", NSStringFromSelector(_cmd));
    [self.adFetcher stopAd];
}

- (void)adInteractionDidEnd {
    ANLogDebug(@"%@", NSStringFromSelector(_cmd));
    [self.adFetcher setupAutoRefreshTimerIfNecessary];
    [self.adFetcher startAutoRefreshTimer];
}
                */

- (NSString *)adTypeForMRAID    {
            //FIX UT consolidate return values as a function of entryPointType?  or isKindOfClass: ...
    ANLogDebug(@"ABSTRACT METHOD.  MUST be implemented by subclass.");
    return @"";
}

- (UIViewController *)displayController {
    ANLogDebug(@"%@ is abstract, should be implemented by subclass", NSStringFromSelector(_cmd));
    return nil;
}

- (ANEntryPointType) entryPointType {
    ANLogDebug(@"ABSTRACT METHOD.  MUST be implemented by subclass.");
    return  ANEntryPointTypeUndefined;
}

- (CGSize) frameSize  {
    return self.frame.size;
}



@end

