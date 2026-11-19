// FLIDE · эффекты поверх игры: ауры вокруг элементов, тени, искры при броске карты, комбо.
// Рисуется отдельным прозрачным окном, касания проходят в игру насквозь.
#import "FlideCore.h"
#import <objc/runtime.h>


UIColor *FlideColorFromHex(NSString *hex) {
    unsigned v = 0x7CF7FF;
    if (hex.length) [[NSScanner scannerWithString:[hex stringByReplacingOccurrencesOfString:@"#" withString:@""]] scanHexInt:&v];
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0 blue:(v & 0xFF) / 255.0 alpha:1];
}

NSString *FlideHexFromColor(UIColor *c) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [c getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)(r * 255), (int)(g * 255), (int)(b * 255)];
}

NSString *FlideFxStyleName(FlideFxStyle s) {
    switch (s) {
        case FlideFxAura:   return @"✨ Аура";
        case FlideFxShadow: return @"🌑 Тень";
        case FlideFxFire:   return @"🔥 Огонь";
        case FlideFxStars:  return @"⭐️ Звёзды";
        case FlideFxRunes:  return @"🔮 Руны";
        default:            return @"?";
    }
}

#pragma mark - картинки частиц

static UIImage *dotImage(void) {
    static UIImage *img;
    if (!img) {
        img = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(32, 32)] imageWithActions:^(UIGraphicsImageRendererContext *c) {
            CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
            CGFloat comps[] = { 1, 1, 1, 1,  1, 1, 1, 0 };
            CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, NULL, 2);
            CGContextDrawRadialGradient(c.CGContext, g, CGPointMake(16, 16), 0, CGPointMake(16, 16), 16, 0);
            CGGradientRelease(g); CGColorSpaceRelease(cs);
        }];
    }
    return img;
}

static UIImage *glyphImage(NSString *glyph, CGFloat size) {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)] imageWithActions:^(UIGraphicsImageRendererContext *c) {
        NSDictionary *attr = @{ NSFontAttributeName: [UIFont systemFontOfSize:size * 0.8 weight:UIFontWeightBold],
                                NSForegroundColorAttributeName: UIColor.whiteColor };
        CGSize s = [glyph sizeWithAttributes:attr];
        [glyph drawAtPoint:CGPointMake((size - s.width) / 2, (size - s.height) / 2) withAttributes:attr];
    }];
}

static CAEmitterCell *cell(UIImage *img, UIColor *color, float birth, float life, float vel, float scale) {
    CAEmitterCell *c = [CAEmitterCell emitterCell];
    c.contents = (__bridge id)img.CGImage;
    c.color = color.CGColor;
    c.birthRate = birth; c.lifetime = life; c.lifetimeRange = life * 0.4;
    c.velocity = vel; c.velocityRange = vel * 0.5;
    c.emissionRange = M_PI * 2;
    c.scale = scale; c.scaleRange = scale * 0.5; c.scaleSpeed = -scale * 0.4;
    c.alphaSpeed = -1.0 / life;
    return c;
}

#pragma mark - сборка эффекта

static CALayer *makeEffect(FlideFxStyle style, UIColor *color, CGFloat radius) {
    CALayer *root = [CALayer layer];
    root.bounds = CGRectMake(0, 0, radius * 2, radius * 2);

    CAEmitterLayer *em = [CAEmitterLayer layer];
    em.frame = root.bounds;
    em.emitterPosition = CGPointMake(radius, radius);
    em.emitterSize = CGSizeMake(radius * 1.6, radius * 1.6);
    em.emitterShape = kCAEmitterLayerCircle;
    em.emitterMode = kCAEmitterLayerOutline;
    em.renderMode = kCAEmitterLayerAdditive;

    switch (style) {
        case FlideFxAura: {
            CAEmitterCell *c = cell(dotImage(), color, 45, 1.6, 14, 0.22);
            c.yAcceleration = -45;
            CAEmitterCell *s = cell(glyphImage(@"✦", 24), color, 6, 1.2, 10, 0.5);
            s.yAcceleration = -30; s.spinRange = 3;
            em.emitterCells = @[c, s];
            break;
        }
        case FlideFxShadow: {
            em.renderMode = kCAEmitterLayerOldestFirst;
            UIColor *smoke = [UIColor colorWithWhite:0.05 alpha:0.55];
            CAEmitterCell *c = cell(dotImage(), smoke, 30, 2.2, 10, 0.9);
            c.yAcceleration = -12; c.alphaSpeed = -0.35;
            em.emitterCells = @[c];
            // три тени, летающие по кругу
            CAReplicatorLayer *rep = [CAReplicatorLayer layer];
            rep.frame = root.bounds;
            rep.instanceCount = 3;
            rep.instanceTransform = CATransform3DMakeRotation(M_PI * 2 / 3, 0, 0, 1);
            CALayer *orb = [CALayer layer];
            orb.bounds = CGRectMake(0, 0, 14, 14);
            orb.cornerRadius = 7;
            orb.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85].CGColor;
            orb.shadowColor = color.CGColor; orb.shadowOpacity = 1; orb.shadowRadius = 8; orb.shadowOffset = CGSizeZero;
            orb.position = CGPointMake(radius, radius * 0.15);
            [rep addSublayer:orb];
            CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
            spin.toValue = @(M_PI * 2); spin.duration = 2.4; spin.repeatCount = HUGE_VALF;
            [rep addAnimation:spin forKey:@"spin"];
            [root addSublayer:rep];
            break;
        }
        case FlideFxFire: {
            em.emitterShape = kCAEmitterLayerLine;
            em.emitterMode = kCAEmitterLayerVolume;
            em.emitterPosition = CGPointMake(radius, radius * 1.6);
            em.emitterSize = CGSizeMake(radius * 1.4, 1);
            UIColor *fire = [UIColor colorWithRed:1 green:0.45 blue:0.1 alpha:1];
            CAEmitterCell *c = cell(dotImage(), color ?: fire, 90, 0.9, 30, 0.5);
            c.emissionLongitude = -M_PI_2; c.emissionRange = 0.4; c.yAcceleration = -120;
            em.emitterCells = @[c];
            break;
        }
        case FlideFxStars: {
            CAEmitterCell *c = cell(glyphImage(@"★", 28), color, 14, 1.4, 20, 0.45);
            c.spinRange = 4; c.alphaRange = 0.5;
            CAEmitterCell *d = cell(dotImage(), UIColor.whiteColor, 30, 0.8, 8, 0.12);
            em.emitterCells = @[c, d];
            break;
        }
        case FlideFxRunes:
        default: {
            NSArray *runes = @[@"ᚠ", @"ᚱ", @"ᚨ", @"ᛟ", @"ᛉ", @"ᚦ"];
            NSMutableArray *cells = [NSMutableArray new];
            for (NSString *r in runes) {
                CAEmitterCell *c = cell(glyphImage(r, 28), color, 3, 2.0, 12, 0.5);
                c.yAcceleration = -25; c.spin = 0.6; c.spinRange = 1.2;
                [cells addObject:c];
            }
            em.emitterCells = cells;
            CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
            spin.toValue = @(M_PI * 2); spin.duration = 6; spin.repeatCount = HUGE_VALF;
            [em addAnimation:spin forKey:@"spin"];
            break;
        }
    }
    [root insertSublayer:em atIndex:0];
    return root;
}

#pragma mark - окно-оверлей

@interface FlidePassWindow : UIWindow
@end
@implementation FlidePassWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { return nil; }
@end

@interface FlideFX ()
- (void)trailAt:(CGPoint)p;
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CALayer *> *auras;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *throwTimes;
@end

static IMP gOrigSendEvent;
static NSMutableDictionary<NSValue *, NSValue *> *gTouchStart;

static CFTimeInterval gLastTrail;

static void flideSendEvent(UIWindow *self, SEL _cmd, UIEvent *event) {
    ((void (*)(id, SEL, UIEvent *))gOrigSendEvent)(self, _cmd, event);
    if (event.type != UIEventTypeTouches || [FlideMenu isOverlayWindow:self]) return;
    BOOL sparks = FBool(kFxTouch), trail = FBool(kFunTrail);
    if (!sparks && !trail) return;
    for (UITouch *t in event.allTouches) {
        NSValue *key = [NSValue valueWithNonretainedObject:t];
        CGPoint p = [t locationInView:nil];
        if (t.phase == UITouchPhaseMoved && trail) {
            CFTimeInterval now = CACurrentMediaTime();
            if (now - gLastTrail > 0.016) { gLastTrail = now; [[FlideFX shared] trailAt:p]; }
        }
        if (!sparks) continue;
        if (t.phase == UITouchPhaseBegan) gTouchStart[key] = [NSValue valueWithCGPoint:p];
        else if (t.phase == UITouchPhaseEnded || t.phase == UITouchPhaseCancelled) {
            NSValue *s = gTouchStart[key];
            [gTouchStart removeObjectForKey:key];
            if (!s) continue;
            CGPoint a = s.CGPointValue;
            if (hypot(p.x - a.x, p.y - a.y) > 40) [[FlideFX shared] cardThrownAt:p];
        }
    }
}

@implementation FlideFX

+ (instancetype)shared {
    static FlideFX *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [FlideFX new]; });
    return s;
}

- (void)start {
    if (self.window) return;
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class]) { scene = (UIWindowScene *)s; break; }
    if (!scene) return;

    self.window = [[FlidePassWindow alloc] initWithWindowScene:scene];
    self.window.windowLevel = UIWindowLevelStatusBar + 1;
    self.window.backgroundColor = UIColor.clearColor;
    self.window.userInteractionEnabled = NO;
    self.window.rootViewController = [UIViewController new];
    self.window.rootViewController.view.backgroundColor = UIColor.clearColor;
    self.window.hidden = NO;

    self.auras = [NSMutableDictionary new];
    self.throwTimes = [NSMutableArray new];
    gTouchStart = [NSMutableDictionary new];

    Method m = class_getInstanceMethod(UIWindow.class, @selector(sendEvent:));
    gOrigSendEvent = method_setImplementation(m, (IMP)flideSendEvent);

    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    self.link.preferredFramesPerSecond = 30;
    [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    [self reloadRules];
}

- (CALayer *)canvas { return self.window.rootViewController.view.layer; }
- (UIView *)overlayView { return self.window.rootViewController.view; }

- (void)trailAt:(CGPoint)p {
    if (!self.window) return;
    UIColor *color = FlideColorFromHex([FDefaults() stringForKey:kFxColor]);
    CALayer *dot = [CALayer layer];
    dot.bounds = CGRectMake(0, 0, 14, 14);
    dot.cornerRadius = 7;
    dot.position = p;
    dot.backgroundColor = color.CGColor;
    dot.shadowColor = color.CGColor; dot.shadowOpacity = 1; dot.shadowRadius = 8; dot.shadowOffset = CGSizeZero;
    [self.canvas addSublayer:dot];
    CABasicAnimation *sc = [CABasicAnimation animationWithKeyPath:@"transform.scale"]; sc.toValue = @0.1;
    CABasicAnimation *op = [CABasicAnimation animationWithKeyPath:@"opacity"]; op.toValue = @0;
    CAAnimationGroup *g = [CAAnimationGroup animation];
    g.animations = @[sc, op]; g.duration = 0.45; g.fillMode = kCAFillModeForwards; g.removedOnCompletion = NO;
    [dot addAnimation:g forKey:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [dot removeFromSuperlayer]; });
}

- (void)highlightAt:(CGPoint)p {
    if (!self.window) return;
    UIColor *color = FlideColorFromHex([FDefaults() stringForKey:kFxColor]);
    for (int i = 0; i < 3; i++) {
        CAShapeLayer *ring = [CAShapeLayer layer];
        ring.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(-30, -30, 60, 60)].CGPath;
        ring.position = p;
        ring.fillColor = [color colorWithAlphaComponent:0.15].CGColor;
        ring.strokeColor = color.CGColor;
        ring.lineWidth = 3;
        ring.opacity = 0;
        [self.canvas addSublayer:ring];
        CABasicAnimation *sc = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        sc.fromValue = @0.4; sc.toValue = @2.2;
        CAKeyframeAnimation *op = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        op.values = @[@0, @1, @0];
        CAAnimationGroup *g = [CAAnimationGroup animation];
        g.animations = @[sc, op]; g.duration = 0.8; g.beginTime = CACurrentMediaTime() + i * 0.35;
        g.fillMode = kCAFillModeBoth; g.removedOnCompletion = NO;
        [ring addAnimation:g forKey:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [ring removeFromSuperlayer]; });
    }
}

- (void)reloadRules {
    for (CALayer *l in self.auras.allValues) [l removeFromSuperlayer];
    [self.auras removeAllObjects];
    NSDictionary *rules = [FDefaults() dictionaryForKey:kAuras];
    [rules enumerateKeysAndObjectsUsingBlock:^(NSString *path, NSDictionary *cfg, BOOL *stop) {
        CALayer *l = makeEffect([cfg[@"style"] integerValue], FlideColorFromHex(cfg[@"color"]), [cfg[@"radius"] doubleValue] ?: 46);
        l.hidden = YES;
        [self.canvas addSublayer:l];
        self.auras[path] = l;
    }];
}

- (void)tick {
    if (!self.auras.count) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self.auras enumerateKeysAndObjectsUsingBlock:^(NSString *path, CALayer *l, BOOL *stop) {
        CGPoint p;
        BOOL found = [[FlideEngine shared] screenPointForPath:path point:&p];
        l.hidden = !found;
        if (found) l.position = p;
    }];
    [CATransaction commit];
}

#pragma mark - броски и комбо

- (void)cardThrownAt:(CGPoint)p {
    CFTimeInterval now = CACurrentMediaTime();
    [self.throwTimes addObject:@(now)];
    while (self.throwTimes.count && now - self.throwTimes.firstObject.doubleValue > 2.5) [self.throwTimes removeObjectAtIndex:0];
    NSUInteger combo = self.throwTimes.count;
    BOOL big = FBool(kFxCombo) && combo >= 3;
    [self burstAt:p big:big];
    if (big) [self showCombo:combo at:p];
    if (FBool(kFunHaptic)) {
        UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc] initWithStyle:big ? UIImpactFeedbackStyleHeavy : UIImpactFeedbackStyleLight];
        [h impactOccurred];
    }
    if (big && FBool(kFunShake)) [[FlideFun shared] shakeScreen];
    [[FlideFun shared] countThrow:combo];
}

- (void)burstAt:(CGPoint)p big:(BOOL)big {
    if (!self.window) return;
    UIColor *color = FlideColorFromHex([FDefaults() stringForKey:kFxColor]);
    FlideFxStyle style = [FDefaults() integerForKey:kFxStyle];
    CALayer *fx = makeEffect(style, color, big ? 90 : 50);
    fx.position = p;
    [self.canvas addSublayer:fx];
    CAEmitterLayer *em = (CAEmitterLayer *)fx.sublayers.firstObject;
    if ([em isKindOfClass:CAEmitterLayer.class]) {
        em.birthRate = big ? 6 : 3;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ em.birthRate = 0; });
    }
    if (big) { // ударная волна
        CAShapeLayer *ring = [CAShapeLayer layer];
        ring.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(-20, -20, 40, 40)].CGPath;
        ring.position = p;
        ring.fillColor = UIColor.clearColor.CGColor;
        ring.strokeColor = color.CGColor;
        ring.lineWidth = 4;
        [self.canvas addSublayer:ring];
        CABasicAnimation *sc = [CABasicAnimation animationWithKeyPath:@"transform.scale"]; sc.toValue = @6;
        CABasicAnimation *op = [CABasicAnimation animationWithKeyPath:@"opacity"]; op.toValue = @0;
        CAAnimationGroup *g = [CAAnimationGroup animation];
        g.animations = @[sc, op]; g.duration = 0.6; g.fillMode = kCAFillModeForwards; g.removedOnCompletion = NO;
        [ring addAnimation:g forKey:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [ring removeFromSuperlayer]; });
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [fx removeFromSuperlayer]; });
}

- (void)showCombo:(NSUInteger)n at:(CGPoint)p {
    UILabel *l = [UILabel new];
    l.text = [NSString stringWithFormat:@"COMBO ×%lu", (unsigned long)n];
    l.font = [UIFont systemFontOfSize:30 weight:UIFontWeightHeavy];
    l.textColor = UIColor.whiteColor;
    l.layer.shadowColor = FlideColorFromHex([FDefaults() stringForKey:kFxColor]).CGColor;
    l.layer.shadowRadius = 12; l.layer.shadowOpacity = 1; l.layer.shadowOffset = CGSizeZero;
    [l sizeToFit];
    l.center = CGPointMake(p.x, p.y - 60);
    l.transform = CGAffineTransformMakeScale(0.3, 0.3);
    [self.window.rootViewController.view addSubview:l];
    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:1 options:0 animations:^{
        l.transform = CGAffineTransformIdentity;
    } completion:^(BOOL f) {
        [UIView animateWithDuration:0.5 delay:0.5 options:0 animations:^{
            l.alpha = 0; l.center = CGPointMake(l.center.x, l.center.y - 40);
        } completion:^(BOOL f2) { [l removeFromSuperview]; }];
    }];
}

@end
