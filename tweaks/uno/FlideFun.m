// FLIDE · приколы: ускорение, радужные тексты, анимация победы, ночной фильтр, FPS, статистика.
#import "FlideCore.h"

@interface FlideFun ()
@property (nonatomic, strong) UILabel *fpsLabel;
@property (nonatomic, strong) UIView *nightView;
@property (nonatomic, assign) NSUInteger frames;
@property (nonatomic, assign) CFTimeInterval fpsStart;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *rainbowHandles;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSData *> *rainbowOrig;
@property (nonatomic, assign) CFTimeInterval lastRainbowScan;
@property (nonatomic, assign) BOOL wasVictory, rainbowWasOn;
@property (nonatomic, assign) float lastSpeed;
@end

@implementation FlideFun

+ (instancetype)shared {
    static FlideFun *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [FlideFun new]; });
    return s;
}

- (void)start {
    self.rainbowHandles = [NSMutableArray new];
    self.rainbowOrig = [NSMutableDictionary new];
    self.lastSpeed = 1;
    [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) { [self secondTick]; }];
    [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) { [self rainbowTick]; }];
    [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *t) { [self victoryTick]; }];
    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(frame)];
    [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    [self bumpStat:@"launches" by:1];
}

#pragma mark - статистика

- (NSDictionary *)stats { return [FDefaults() dictionaryForKey:kStats] ?: @{}; }
- (void)resetStats { [FDefaults() removeObjectForKey:kStats]; }

- (void)bumpStat:(NSString *)k by:(double)v {
    NSMutableDictionary *d = [[self stats] mutableCopy];
    d[k] = @([d[k] doubleValue] + v);
    [FDefaults() setObject:d forKey:kStats];
}

- (void)maxStat:(NSString *)k value:(double)v {
    NSMutableDictionary *d = [[self stats] mutableCopy];
    if (v > [d[k] doubleValue]) { d[k] = @(v); [FDefaults() setObject:d forKey:kStats]; }
}

- (void)countThrow:(NSUInteger)combo {
    [self bumpStat:@"throws" by:1];
    [self maxStat:@"bestCombo" value:combo];
}

#pragma mark - секундный тик: ускорение, время, FPS-лейбл, ночь

- (void)secondTick {
    if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) [self bumpStat:@"seconds" by:1];
    [self applySpeed];
    [self applyNight];
    [self updateFPSLabelVisibility];
}

- (void)applySpeed {
    if (!FIL_Ready()) return;
    float speed = [FDefaults() floatForKey:kFunSpeed];
    if (speed < 1) speed = 1;
    // трогаем timeScale только если включено ускорение или нужно вернуть 1
    if (speed == 1 && self.lastSpeed == 1) return;
    void *a[1] = { &speed };
    FIL_Static("UnityEngine", "Time", "set_timeScale", 1, a);
    self.lastSpeed = speed;
}

- (void)applyNight {
    UIView *host = [[FlideFX shared] overlayView];
    if (!host) return;
    float a = [FDefaults() floatForKey:kFunNight];
    if (a <= 0.01) { [self.nightView removeFromSuperview]; self.nightView = nil; return; }
    if (!self.nightView) {
        self.nightView = [[UIView alloc] initWithFrame:host.bounds];
        self.nightView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.nightView.userInteractionEnabled = NO;
        self.nightView.backgroundColor = [UIColor colorWithRed:1 green:0.55 blue:0.15 alpha:1];
        [host insertSubview:self.nightView atIndex:0];
    }
    self.nightView.alpha = MIN(a, 0.45);
}

#pragma mark - FPS

- (void)frame {
    self.frames++;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - self.fpsStart >= 0.5) {
        double fps = self.frames / (now - self.fpsStart);
        self.frames = 0; self.fpsStart = now;
        if (self.fpsLabel) self.fpsLabel.text = [NSString stringWithFormat:@" %.0f FPS ", fps];
    }
}

- (void)updateFPSLabelVisibility {
    UIView *host = [[FlideFX shared] overlayView];
    if (!FBool(kFunFPS) || !host) { [self.fpsLabel removeFromSuperview]; self.fpsLabel = nil; return; }
    if (self.fpsLabel) return;
    self.fpsLabel = [UILabel new];
    self.fpsLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightBold];
    self.fpsLabel.textColor = UIColor.greenColor;
    self.fpsLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    self.fpsLabel.layer.cornerRadius = 6; self.fpsLabel.clipsToBounds = YES;
    self.fpsLabel.frame = CGRectMake(host.safeAreaInsets.left + 8, host.safeAreaInsets.top + 6, 70, 18);
    [host addSubview:self.fpsLabel];
}

#pragma mark - радужные тексты

- (void)rainbowTick {
    BOOL on = FBool(kFunRainbow);
    if (!FIL_Ready()) return;
    Il2CppClass *graphic = FIL_Class("UnityEngine.UI", "Graphic");
    if (!on) {
        if (self.rainbowWasOn) { // вернуть исходные цвета
            for (NSNumber *h in self.rainbowHandles) {
                void *o = FIL_Target(h.unsignedIntValue);
                NSData *c = self.rainbowOrig[h];
                if (o && c) FIL_Call1(o, "set_color", (void *)c.bytes);
                FIL_Unpin(h.unsignedIntValue);
            }
            [self.rainbowHandles removeAllObjects];
            [self.rainbowOrig removeAllObjects];
            self.rainbowWasOn = NO;
        }
        return;
    }
    self.rainbowWasOn = YES;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - self.lastRainbowScan > 3) {
        self.lastRainbowScan = now;
        NSMutableArray *objs = [NSMutableArray new];
        if (FIL_Class("TMPro", "TMP_Text")) [objs addObjectsFromArray:FIL_FindAll("TMPro", "TMP_Text")];
        else { [objs addObjectsFromArray:FIL_FindAll("TMPro", "TextMeshProUGUI")]; }
        [objs addObjectsFromArray:FIL_FindAll("UnityEngine.UI", "Text")];
        NSMutableSet *have = [NSMutableSet new];
        for (NSNumber *h in self.rainbowHandles) {
            void *o = FIL_Target(h.unsignedIntValue);
            if (o) [have addObject:[NSValue valueWithPointer:o]];
        }
        for (NSValue *v in objs) {
            if ([have containsObject:v] || !FIL_ActiveInHierarchy(v.pointerValue)) continue;
            if (graphic && !FIL_IsSubclass(FIL_ClassOf(v.pointerValue), graphic) && !FIL_Class("TMPro", "TMP_Text")) continue;
            uint32_t h = FIL_Pin(v.pointerValue);
            float *c = FIL_Unbox(FIL_Call0(v.pointerValue, "get_color"));
            if (c) self.rainbowOrig[@(h)] = [NSData dataWithBytes:c length:16];
            [self.rainbowHandles addObject:@(h)];
            if (self.rainbowHandles.count > 120) break;
        }
    }
    NSUInteger i = 0;
    for (NSNumber *h in self.rainbowHandles) {
        void *o = FIL_Target(h.unsignedIntValue);
        if (!o) continue;
        UIColor *col = [UIColor colorWithHue:fmod(now * 0.25 + i++ * 0.07, 1.0) saturation:0.75 brightness:1 alpha:1];
        CGFloat r, g, b, a;
        [col getRed:&r green:&g blue:&b alpha:&a];
        float rgba[4] = { (float)r, (float)g, (float)b, 1 };
        NSData *orig = self.rainbowOrig[h];
        if (orig) rgba[3] = ((const float *)orig.bytes)[3];
        FIL_Call1(o, "set_color", rgba);
    }
}

#pragma mark - победа

- (BOOL)victoryVisible {
    static NSArray *words;
    if (!words) words = @[@"win", @"victory", @"winner", @"побед", @"выигр", @"1st"];
    NSMutableArray *objs = [NSMutableArray new];
    if (FIL_Class("TMPro", "TMP_Text")) [objs addObjectsFromArray:FIL_FindAll("TMPro", "TMP_Text")];
    else [objs addObjectsFromArray:FIL_FindAll("TMPro", "TextMeshProUGUI")];
    [objs addObjectsFromArray:FIL_FindAll("UnityEngine.UI", "Text")];
    for (NSValue *v in objs) {
        NSString *t = FIL_ToNSString(FIL_Call0(v.pointerValue, "get_text")).lowercaseString;
        if (t.length == 0 || t.length > 40) continue;
        for (NSString *w in words)
            if ([t containsString:w] && FIL_ActiveInHierarchy(v.pointerValue)) return YES;
    }
    return NO;
}

- (void)victoryTick {
    if (!FBool(kFunConfetti) || !FIL_Ready()) return;
    BOOL v = [self victoryVisible];
    if (v && !self.wasVictory) { [self victoryNow]; [self bumpStat:@"wins" by:1]; }
    self.wasVictory = v;
}

- (void)victoryNow {
    NSInteger style = [FDefaults() integerForKey:kVictoryStyle];
    if (style == 0 || style == 2) [self confettiNow];
    if (style == 1 || style == 2) [self fireworksNow];
    NSString *text = [FDefaults() stringForKey:kVictoryText];
    if (text.length) [self bigText:text];
    if (FBool(kFunHaptic)) [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
}

- (void)bigText:(NSString *)text {
    UIView *host = [[FlideFX shared] overlayView];
    if (!host) return;
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = [UIFont systemFontOfSize:54 weight:UIFontWeightBlack];
    l.textColor = UIColor.whiteColor;
    l.textAlignment = NSTextAlignmentCenter;
    l.adjustsFontSizeToFitWidth = YES;
    l.layer.shadowColor = FlideColorFromHex([FDefaults() stringForKey:kFxColor]).CGColor;
    l.layer.shadowRadius = 18; l.layer.shadowOpacity = 1; l.layer.shadowOffset = CGSizeZero;
    l.frame = CGRectMake(20, host.bounds.size.height / 2 - 40, host.bounds.size.width - 40, 80);
    l.transform = CGAffineTransformMakeScale(0.2, 0.2);
    [host addSubview:l];
    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.45 initialSpringVelocity:1 options:0 animations:^{
        l.transform = CGAffineTransformIdentity;
    } completion:^(BOOL f) {
        [UIView animateWithDuration:0.6 delay:1.6 options:0 animations:^{ l.alpha = 0; } completion:^(BOOL f2) { [l removeFromSuperview]; }];
    }];
}

static UIImage *rectImage(void) {
    static UIImage *img;
    if (!img) img = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(10, 6)] imageWithActions:^(UIGraphicsImageRendererContext *c) {
        [UIColor.whiteColor setFill]; UIRectFill(CGRectMake(0, 0, 10, 6));
    }];
    return img;
}

- (void)confettiNow {
    UIView *host = [[FlideFX shared] overlayView];
    if (!host) return;
    CAEmitterLayer *em = [CAEmitterLayer layer];
    em.emitterPosition = CGPointMake(host.bounds.size.width / 2, -10);
    em.emitterSize = CGSizeMake(host.bounds.size.width, 1);
    em.emitterShape = kCAEmitterLayerLine;
    NSMutableArray *cells = [NSMutableArray new];
    for (UIColor *c in @[UIColor.systemRedColor, UIColor.systemYellowColor, UIColor.systemGreenColor, UIColor.systemBlueColor,
                         UIColor.systemPinkColor, FlideColorFromHex([FDefaults() stringForKey:kFxColor])]) {
        CAEmitterCell *cell = [CAEmitterCell emitterCell];
        cell.contents = (__bridge id)rectImage().CGImage;
        cell.color = c.CGColor;
        cell.birthRate = 18; cell.lifetime = 6;
        cell.velocity = 160; cell.velocityRange = 80;
        cell.emissionLongitude = M_PI; cell.emissionRange = 0.6;
        cell.yAcceleration = 120;
        cell.spin = 4; cell.spinRange = 8;
        cell.scale = 1.2; cell.scaleRange = 0.6;
        [cells addObject:cell];
    }
    em.emitterCells = cells;
    [host.layer addSublayer:em];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ em.birthRate = 0; });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [em removeFromSuperlayer]; });
}

- (void)fireworksNow {
    UIView *host = [[FlideFX shared] overlayView];
    if (!host) return;
    CGSize s = host.bounds.size;
    for (int i = 0; i < 6; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            CGPoint p = CGPointMake(s.width * (0.15 + 0.7 * drand48()), s.height * (0.15 + 0.4 * drand48()));
            [[FlideFX shared] burstAt:p big:YES];
        });
    }
}

- (void)shakeScreen {
    UIWindow *game = nil;
    for (UIScene *sc in UIApplication.sharedApplication.connectedScenes)
        if ([sc isKindOfClass:UIWindowScene.class])
            for (UIWindow *w in ((UIWindowScene *)sc).windows)
                if (w.isKeyWindow || (!game && w.rootViewController && ![FlideMenu isOverlayWindow:w])) game = w;
    CAKeyframeAnimation *a = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    a.values = @[@0, @-12, @10, @-8, @6, @-3, @0];
    a.duration = 0.4;
    [game.layer addAnimation:a forKey:@"flide.shake"];
}

@end
