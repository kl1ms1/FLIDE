// FLIDE · бут-лого: анимированная заставка при запуске игры.
// По умолчанию — стеклянная карточка «✦ FLIDE» с искрами.
// В меню можно поставить свою картинку (Documents/FLIDE/bootlogo.png).
#import "FlideCore.h"

@interface FlideBootWindow : UIWindow
@end
@implementation FlideBootWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { return nil; } // игра не блокируется
@end

static UIWindow *gBootWindow;

NSString *FlideBootLogoPath(void) {
    return [FlideDir(nil) stringByAppendingPathComponent:@"bootlogo.png"];
}

@implementation FlideBoot

+ (UIWindowScene *)scene {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class]) return (UIWindowScene *)s;
    return nil;
}

+ (UIView *)defaultLogoInView:(UIView *)root {
    UIColor *accent = FlideColorFromHex([FDefaults() stringForKey:kFxColor]);

    // стеклянная карточка
    UIVisualEffect *effect = nil;
    Class glass = NSClassFromString(@"UIGlassEffect");
    effect = glass ? [glass new] : [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:effect];
    card.frame = CGRectMake(0, 0, 260, 130);
    card.layer.cornerRadius = 32;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;
    card.layer.borderWidth = 1;
    card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 26, 260, 54)];
    title.text = @"✦ FLIDE";
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont systemFontOfSize:46 weight:UIFontWeightHeavy];
    title.textColor = UIColor.whiteColor;
    [card.contentView addSubview:title];

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(0, 82, 260, 20)];
    sub.text = @"кастомизация · без рекламы";
    sub.textAlignment = NSTextAlignmentCenter;
    sub.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    sub.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    [card.contentView addSubview:sub];

    // блик, пробегающий по тексту
    CAGradientLayer *shine = [CAGradientLayer layer];
    shine.frame = CGRectMake(-260, 0, 260, 130);
    shine.colors = @[(id)UIColor.clearColor.CGColor, (id)[UIColor colorWithWhite:1 alpha:0.45].CGColor, (id)UIColor.clearColor.CGColor];
    shine.startPoint = CGPointMake(0, 0.3); shine.endPoint = CGPointMake(1, 0.7);
    [card.contentView.layer addSublayer:shine];
    CABasicAnimation *run = [CABasicAnimation animationWithKeyPath:@"position.x"];
    run.fromValue = @(-130); run.toValue = @(390); run.duration = 1.4; run.beginTime = CACurrentMediaTime() + 0.4;
    run.repeatCount = 2;
    [shine addAnimation:run forKey:nil];

    // свечение акцентным цветом
    UIView *wrap = [[UIView alloc] initWithFrame:card.frame];
    wrap.layer.shadowColor = accent.CGColor;
    wrap.layer.shadowRadius = 30;
    wrap.layer.shadowOpacity = 0.9;
    wrap.layer.shadowOffset = CGSizeZero;
    [wrap addSubview:card];
    return wrap;
}

+ (void)showAnimated {
    if (gBootWindow) return;
    UIWindowScene *scene = [self scene];
    if (!scene) return;

    UIWindow *w = [[FlideBootWindow alloc] initWithWindowScene:scene];
    w.windowLevel = UIWindowLevelAlert + 10;
    w.backgroundColor = UIColor.clearColor;
    w.rootViewController = [UIViewController new];
    UIView *root = w.rootViewController.view;
    root.backgroundColor = UIColor.blackColor;
    w.hidden = NO;
    gBootWindow = w;

    UIView *logo = nil;
    UIImage *custom = [UIImage imageWithContentsOfFile:FlideBootLogoPath()];
    if (custom) {
        CGSize b = root.bounds.size;
        CGFloat k = MIN(MIN(b.width * 0.7 / custom.size.width, b.height * 0.6 / custom.size.height), 1.5);
        UIImageView *iv = [[UIImageView alloc] initWithImage:custom];
        iv.frame = CGRectMake(0, 0, custom.size.width * k, custom.size.height * k);
        iv.contentMode = UIViewContentModeScaleAspectFit;
        logo = iv;
    } else {
        logo = [self defaultLogoInView:root];
    }
    logo.center = CGPointMake(CGRectGetMidX(root.bounds), CGRectGetMidY(root.bounds));
    logo.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                            UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [root addSubview:logo];
    NSInteger anim = [FDefaults() integerForKey:kBootAnim];
    void (^ring)(void) = ^{
        // волна акцентного цвета от логотипа
        CAShapeLayer *ring = [CAShapeLayer layer];
        ring.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(-40, -40, 80, 80)].CGPath;
        ring.position = logo.center;
        ring.fillColor = UIColor.clearColor.CGColor;
        ring.strokeColor = FlideColorFromHex([FDefaults() stringForKey:kFxColor]).CGColor;
        ring.lineWidth = 3;
        [root.layer insertSublayer:ring below:logo.layer];
        CABasicAnimation *sc = [CABasicAnimation animationWithKeyPath:@"transform.scale"]; sc.toValue = @8;
        CABasicAnimation *op = [CABasicAnimation animationWithKeyPath:@"opacity"]; op.toValue = @0;
        CAAnimationGroup *g = [CAAnimationGroup animation];
        g.animations = @[sc, op]; g.duration = 1.0; g.fillMode = kCAFillModeForwards; g.removedOnCompletion = NO;
        [ring addAnimation:g forKey:nil];
    };

    if (anim == 1) { // вспышка
        UIView *flash = [[UIView alloc] initWithFrame:root.bounds];
        flash.backgroundColor = UIColor.whiteColor;
        flash.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [root addSubview:flash];
        logo.transform = CGAffineTransformMakeScale(1.4, 1.4);
        [UIView animateWithDuration:0.6 delay:0.05 options:UIViewAnimationOptionCurveEaseOut animations:^{
            flash.alpha = 0;
            logo.transform = CGAffineTransformIdentity;
        } completion:^(BOOL f) { [flash removeFromSuperview]; ring(); }];
    } else if (anim == 2) { // глитч: дрожание и цветные сдвиги
        logo.alpha = 1;
        UIColor *accent = FlideColorFromHex([FDefaults() stringForKey:kFxColor]);
        for (int i = 0; i < 9; i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.07 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                BOOL last = i == 8;
                logo.transform = last ? CGAffineTransformIdentity
                                      : CGAffineTransformMakeTranslation((drand48() - 0.5) * 30, (drand48() - 0.5) * 10);
                logo.alpha = last ? 1 : 0.5 + drand48() * 0.5;
                logo.layer.shadowColor = (i % 2 ? accent : UIColor.systemRedColor).CGColor;
                logo.layer.shadowOffset = last ? CGSizeZero : CGSizeMake((drand48() - 0.5) * 16, 0);
                logo.layer.shadowOpacity = 1; logo.layer.shadowRadius = last ? 24 : 0;
                if (last) ring();
            });
        }
    } else if (anim == 3 && !custom) { // печатная машинка
        logo.alpha = 1;
        UILabel *title = nil;
        for (UIView *v in [logo.subviews.firstObject isKindOfClass:UIVisualEffectView.class]
                 ? ((UIVisualEffectView *)logo.subviews.firstObject).contentView.subviews : @[])
            if ([v isKindOfClass:UILabel.class]) { title = (UILabel *)v; break; }
        NSString *full = title.text ?: @"";
        title.text = @"";
        for (NSUInteger i = 1; i <= full.length; i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((0.1 + i * 0.09) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                title.text = [full substringToIndex:i];
                if (i == full.length) ring();
            });
        }
    } else { // пружинка
        logo.alpha = 0;
        logo.transform = CGAffineTransformMakeScale(0.6, 0.6);
        [UIView animateWithDuration:0.7 delay:0.1 usingSpringWithDamping:0.6 initialSpringVelocity:0.8 options:0 animations:^{
            logo.alpha = 1;
            logo.transform = CGAffineTransformIdentity;
        } completion:^(BOOL f) { ring(); }];
    }

    double hold = [FDefaults() doubleForKey:kBootSeconds] ?: 2.2;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(hold * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.5 animations:^{
            root.alpha = 0;
            logo.transform = CGAffineTransformMakeScale(1.15, 1.15);
        } completion:^(BOOL f) {
            gBootWindow.hidden = YES;
            gBootWindow = nil;
        }];
    });
}

+ (void)install {
    __block id token = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                                         object:nil queue:nil usingBlock:^(NSNotification *n) {
        [[NSNotificationCenter defaultCenter] removeObserver:token];
        if (FBool(kBoot)) [self showAnimated];
    }];
}

+ (BOOL)setCustomImage:(UIImage *)img {
    if (!img) {
        [NSFileManager.defaultManager removeItemAtPath:FlideBootLogoPath() error:nil];
        return YES;
    }
    // ограничим размер, чтобы заставка грузилась мгновенно
    CGFloat k = MIN(1.0, 1200.0 / MAX(img.size.width, img.size.height));
    CGSize s = CGSizeMake(img.size.width * k, img.size.height * k);
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat];
    f.scale = 1;
    NSData *png = [[[UIGraphicsImageRenderer alloc] initWithSize:s format:f] PNGDataWithActions:^(UIGraphicsImageRendererContext *c) {
        [img drawInRect:CGRectMake(0, 0, s.width, s.height)];
    }];
    return [png writeToFile:FlideBootLogoPath() atomically:YES];
}

+ (NSArray<NSString *> *)animationNames { return @[@"Пружинка", @"Вспышка", @"Глитч", @"Печатная машинка"]; }

+ (BOOL)hasCustomImage {
    return [NSFileManager.defaultManager fileExistsAtPath:FlideBootLogoPath()];
}

@end
