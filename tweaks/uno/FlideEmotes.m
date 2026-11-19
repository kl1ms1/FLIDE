// FLIDE · свои эмоции и подарки.
// ВСЁ ЛОКАЛЬНО: рисуется поверх игры только на твоём экране, на сервер ничего
// не отправляется, другие игроки этого не видят. Подарки — наши собственные
// анимации и твои картинки, а не платные товары игры.
#import "FlideCore.h"

@implementation FlideEmotes

+ (instancetype)shared {
    static FlideEmotes *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [FlideEmotes new]; });
    return s;
}

#pragma mark - хранилище

- (NSArray<NSString *> *)filesIn:(NSString *)sub {
    NSString *dir = FlideDir(sub);
    NSMutableArray *out = [NSMutableArray new];
    for (NSString *f in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil] sortedArrayUsingSelector:@selector(compare:)])
        if ([f hasSuffix:@".png"]) [out addObject:[dir stringByAppendingPathComponent:f]];
    return out;
}

- (BOOL)save:(UIImage *)img into:(NSString *)sub {
    CGFloat k = MIN(1.0, 256.0 / MAX(img.size.width, img.size.height));
    CGSize s = CGSizeMake(round(img.size.width * k), round(img.size.height * k));
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat];
    f.scale = 1;
    NSData *png = [[[UIGraphicsImageRenderer alloc] initWithSize:s format:f] PNGDataWithActions:^(UIGraphicsImageRendererContext *c) {
        [img drawInRect:CGRectMake(0, 0, s.width, s.height)];
    }];
    NSString *name = [NSString stringWithFormat:@"%.0f.png", NSDate.date.timeIntervalSince1970 * 1000];
    return [png writeToFile:[FlideDir(sub) stringByAppendingPathComponent:name] atomically:YES];
}

- (NSArray<NSString *> *)builtinEmotes {
    return @[@"😂", @"🔥", @"😎", @"👑", @"💀", @"🥶", @"🤡", @"❤️", @"😡", @"🥳", @"🤯", @"👀", @"🫡", @"💅", @"🗿", @"😈"];
}
- (NSArray<NSString *> *)customEmotes { return [self filesIn:@"emotes"]; }
- (BOOL)addCustomEmote:(UIImage *)img { return [self save:img into:@"emotes"]; }
- (void)removeCustomEmote:(NSString *)path { [NSFileManager.defaultManager removeItemAtPath:path error:nil]; }

- (NSArray<NSDictionary *> *)builtinGifts {
    return @[@{@"id": @"cake",    @"title": @"Торт",      @"icon": @"🎂"},
             @{@"id": @"crown",   @"title": @"Корона",    @"icon": @"👑"},
             @{@"id": @"fire",    @"title": @"Фейерверк", @"icon": @"🎆"},
             @{@"id": @"hearts",  @"title": @"Сердца",    @"icon": @"💖"},
             @{@"id": @"roses",   @"title": @"Розы",      @"icon": @"🌹"},
             @{@"id": @"rocket",  @"title": @"Ракета",    @"icon": @"🚀"},
             @{@"id": @"diamond", @"title": @"Алмаз",     @"icon": @"💎"},
             @{@"id": @"cup",     @"title": @"Кубок",     @"icon": @"🏆"},
             @{@"id": @"money",   @"title": @"Дождь",     @"icon": @"💸"},
             @{@"id": @"ghost",   @"title": @"Призрак",   @"icon": @"👻"}];
}
- (NSArray<NSString *> *)customGifts { return [self filesIn:@"gifts"]; }
- (BOOL)addCustomGift:(UIImage *)img { return [self save:img into:@"gifts"]; }
- (void)removeCustomGift:(NSString *)path { [NSFileManager.defaultManager removeItemAtPath:path error:nil]; }

#pragma mark - отрисовка

static UIImage *emojiImage(NSString *e, CGFloat size) {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)] imageWithActions:^(UIGraphicsImageRendererContext *c) {
        NSDictionary *a = @{NSFontAttributeName: [UIFont systemFontOfSize:size * 0.82]};
        CGSize s = [e sizeWithAttributes:a];
        [e drawAtPoint:CGPointMake((size - s.width) / 2, (size - s.height) / 2) withAttributes:a];
    }];
}

static UIImage *imageFor(id thing, CGFloat size) {
    if ([thing isKindOfClass:NSString.class] && [(NSString *)thing hasPrefix:@"/"])
        return [UIImage imageWithContentsOfFile:thing];
    if ([thing isKindOfClass:NSDictionary.class]) return emojiImage(thing[@"icon"], size);
    if ([thing isKindOfClass:NSString.class]) return emojiImage(thing, size);
    return nil;
}

- (UIView *)host { return [[FlideFX shared] overlayView]; }

- (CGPoint)myPoint {
    CGPoint p;
    NSString *me = [FDefaults() stringForKey:kMyAvatar];
    if (me && [[FlideEngine shared] screenPointForPath:me point:&p]) return p;
    UIView *h = [self host];
    return CGPointMake(h.bounds.size.width / 2, h.bounds.size.height * 0.78);
}

- (void)sendEmote:(id)emote {
    UIView *h = [self host];
    UIImage *img = imageFor(emote, 120);
    if (!h || !img) return;
    CGPoint from = [self myPoint];
    UIImageView *iv = [[UIImageView alloc] initWithImage:img];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.frame = CGRectMake(0, 0, 84, 84);
    iv.center = from;
    iv.transform = CGAffineTransformMakeScale(0.1, 0.1);
    // пузырь-подложка
    UIView *bubble = [[UIView alloc] initWithFrame:CGRectInset(iv.bounds, -10, -10)];
    bubble.backgroundColor = [UIColor colorWithWhite:1 alpha:0.18];
    bubble.layer.cornerRadius = bubble.bounds.size.width / 2;
    bubble.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.5].CGColor;
    bubble.layer.borderWidth = 1;
    bubble.center = CGPointMake(iv.bounds.size.width / 2, iv.bounds.size.height / 2);
    [iv insertSubview:bubble atIndex:0];
    [h addSubview:iv];
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.45 initialSpringVelocity:1.2 options:0 animations:^{
        iv.transform = CGAffineTransformIdentity;
        iv.center = CGPointMake(from.x, from.y - 70);
    } completion:^(BOOL f) {
        CABasicAnimation *wob = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        wob.fromValue = @(-0.15); wob.toValue = @0.15; wob.duration = 0.18; wob.autoreverses = YES; wob.repeatCount = 3;
        [iv.layer addAnimation:wob forKey:nil];
        [UIView animateWithDuration:0.6 delay:1.4 options:0 animations:^{
            iv.alpha = 0;
            iv.center = CGPointMake(from.x, from.y - 130);
        } completion:^(BOOL f2) { [iv removeFromSuperview]; }];
    }];
    if (FBool(kFunHaptic)) [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
}

- (void)rain:(UIImage *)img count:(int)n in:(UIView *)h {
    CGSize s = h.bounds.size;
    for (int i = 0; i < n; i++) {
        UIImageView *d = [[UIImageView alloc] initWithImage:img];
        CGFloat size = 26 + arc4random_uniform(26);
        d.frame = CGRectMake(arc4random_uniform((uint32_t)s.width), -60, size, size);
        [h addSubview:d];
        double delay = i * 0.06, dur = 1.8 + drand48();
        [UIView animateWithDuration:dur delay:delay options:UIViewAnimationOptionCurveEaseIn animations:^{
            d.center = CGPointMake(d.center.x + (drand48() - 0.5) * 80, s.height + 60);
            d.transform = CGAffineTransformMakeRotation((drand48() - 0.5) * 4);
        } completion:^(BOOL f) { [d removeFromSuperview]; }];
    }
}

- (void)sendGift:(id)gift toPoint:(NSValue *)target {
    UIView *h = [self host];
    UIImage *img = imageFor(gift, 160);
    if (!h || !img) return;
    CGPoint to = target ? target.CGPointValue : [self myPoint];
    CGPoint from = CGPointMake(h.bounds.size.width / 2, h.bounds.size.height + 80);
    NSString *gid = [gift isKindOfClass:NSDictionary.class] ? gift[@"id"] : @"custom";

    UIImageView *iv = [[UIImageView alloc] initWithImage:img];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.frame = CGRectMake(0, 0, 110, 110);
    iv.center = from;
    iv.layer.shadowColor = FlideColorFromHex([FDefaults() stringForKey:kFxColor]).CGColor;
    iv.layer.shadowRadius = 20; iv.layer.shadowOpacity = 1; iv.layer.shadowOffset = CGSizeZero;
    [h addSubview:iv];

    // полёт по дуге
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:from];
    [path addQuadCurveToPoint:to controlPoint:CGPointMake((from.x + to.x) / 2 + 120, MIN(from.y, to.y) - 160)];
    CAKeyframeAnimation *fly = [CAKeyframeAnimation animationWithKeyPath:@"position"];
    fly.path = path.CGPath;
    fly.duration = 0.9;
    fly.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    iv.layer.position = to;
    [iv.layer addAnimation:fly forKey:nil];
    if ([gid isEqualToString:@"rocket"]) iv.transform = CGAffineTransformMakeRotation(-M_PI_4);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[FlideFX shared] burstAt:to big:YES];
        if ([gid isEqualToString:@"fire"]) [[FlideFun shared] fireworksNow];
        else if ([gid isEqualToString:@"hearts"]) [self rain:emojiImage(@"💖", 60) count:30 in:h];
        else if ([gid isEqualToString:@"roses"]) [self rain:emojiImage(@"🌹", 60) count:24 in:h];
        else if ([gid isEqualToString:@"money"]) [self rain:emojiImage(@"💸", 60) count:36 in:h];
        else if ([gid isEqualToString:@"cup"] || [gid isEqualToString:@"crown"]) [[FlideFun shared] confettiNow];
        else if ([gid isEqualToString:@"ghost"]) {
            [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionAutoreverse | UIViewAnimationOptionRepeat animations:^{ iv.alpha = 0.3; } completion:nil];
        }
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.4 initialSpringVelocity:1 options:0 animations:^{
            iv.transform = CGAffineTransformMakeScale(1.35, 1.35);
        } completion:^(BOOL f) {
            [UIView animateWithDuration:0.7 delay:1.6 options:0 animations:^{
                iv.alpha = 0; iv.transform = CGAffineTransformMakeScale(0.4, 0.4);
            } completion:^(BOOL f2) { [iv.layer removeAllAnimations]; [iv removeFromSuperview]; }];
        }];
        if (FBool(kFunHaptic)) [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    });
}

@end
