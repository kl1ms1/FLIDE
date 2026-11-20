// FLIDE · свои эмоции и подарки в стиле игры.
// ВСЁ ЛОКАЛЬНО: рисуется поверх игры только на твоём экране, на сервер ничего не
// отправляется, другие игроки этого не видят. Подарки — наши собственные анимации
// и твои картинки, а не платные товары игры.
#import "FlideCore.h"

static NSString *const kSlots = @"flide.emote.slots";

@interface FlideEmotes ()
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *seatHandles; // место 1…4 → Graphic
@property (nonatomic, assign) CFTimeInterval seatsAt;
@end

@implementation FlideEmotes

+ (instancetype)shared {
    static FlideEmotes *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [FlideEmotes new]; s.seatHandles = [NSMutableDictionary new]; });
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

- (NSString *)save:(UIImage *)img into:(NSString *)sub {
    CGFloat k = MIN(1.0, 256.0 / MAX(img.size.width, img.size.height));
    CGSize s = CGSizeMake(round(img.size.width * k), round(img.size.height * k));
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat];
    f.scale = 1;
    NSData *png = [[[UIGraphicsImageRenderer alloc] initWithSize:s format:f] PNGDataWithActions:^(UIGraphicsImageRendererContext *c) {
        [img drawInRect:CGRectMake(0, 0, s.width, s.height)];
    }];
    NSString *path = [FlideDir(sub) stringByAppendingPathComponent:[NSString stringWithFormat:@"%.0f.png", NSDate.date.timeIntervalSince1970 * 1000]];
    return [png writeToFile:path atomically:YES] ? path : nil;
}

- (NSArray<NSString *> *)builtinEmotes {
    return @[@"😂", @"🔥", @"😎", @"👑", @"💀", @"🥶", @"🤡", @"❤️", @"😡", @"🥳", @"🤯", @"👀", @"🫡", @"💅", @"🗿", @"😈"];
}
- (NSArray<NSString *> *)customEmotes { return [self filesIn:@"emotes"]; }
- (BOOL)addCustomEmote:(UIImage *)img { return [self save:img into:@"emotes"] != nil; }
- (void)removeCustomEmote:(NSString *)path {
    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    NSMutableArray *s = [[self slots] mutableCopy];
    for (NSUInteger i = 0; i < s.count; i++) if ([s[i] isEqual:path]) s[i] = [self builtinEmotes][i % 16];
    [FDefaults() setObject:s forKey:kSlots];
}

// 8 слотов быстрой панели — меняются как хочешь
- (NSArray *)slots {
    NSArray *s = [FDefaults() arrayForKey:kSlots];
    if (s.count == 8) return s;
    return [[self builtinEmotes] subarrayWithRange:NSMakeRange(0, 8)];
}
- (void)setSlot:(NSUInteger)i to:(id)thing {
    NSMutableArray *s = [[self slots] mutableCopy];
    if (i < s.count && thing) s[i] = thing;
    [FDefaults() setObject:s forKey:kSlots];
}
- (NSString *)slotFromImage:(UIImage *)img { return [self save:img into:@"emotes"]; }

- (NSArray<NSDictionary *> *)builtinGifts {
    return @[@{@"id": @"egg",     @"title": L(@"Яйцо"),      @"icon": @"🥚"},
             @{@"id": @"tomato",  @"title": L(@"Помидор"),   @"icon": @"🍅"},
             @{@"id": @"cake",    @"title": L(@"Торт"),      @"icon": @"🎂"},
             @{@"id": @"crown",   @"title": L(@"Корона"),    @"icon": @"👑"},
             @{@"id": @"fire",    @"title": L(@"Фейерверк"), @"icon": @"🎆"},
             @{@"id": @"hearts",  @"title": L(@"Сердца"),    @"icon": @"💖"},
             @{@"id": @"roses",   @"title": L(@"Розы"),      @"icon": @"🌹"},
             @{@"id": @"rocket",  @"title": L(@"Ракета"),    @"icon": @"🚀"},
             @{@"id": @"diamond", @"title": L(@"Алмаз"),     @"icon": @"💎"},
             @{@"id": @"cup",     @"title": L(@"Кубок"),     @"icon": @"🏆"},
             @{@"id": @"money",   @"title": L(@"Дождь"),     @"icon": @"💸"},
             @{@"id": @"bomb",    @"title": L(@"Бомба"),     @"icon": @"💣"},
             @{@"id": @"ghost",   @"title": L(@"Призрак"),   @"icon": @"👻"}];
}
- (NSArray<NSString *> *)customGifts { return [self filesIn:@"gifts"]; }
- (BOOL)addCustomGift:(UIImage *)img { return [self save:img into:@"gifts"] != nil; }
- (void)removeCustomGift:(NSString *)path { [NSFileManager.defaultManager removeItemAtPath:path error:nil]; }

#pragma mark - места игроков (настоящие имена из GameDeckWnd)

// Место 1 — ты (HeadTemplate_1), 2…4 — соперники. Берём картинку аватара внутри.
- (void)refreshSeats {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - self.seatsAt < 4 && self.seatHandles.count) return;
    self.seatsAt = now;
    for (NSNumber *h in self.seatHandles.allValues) FIL_Unpin(h.unsignedIntValue);
    [self.seatHandles removeAllObjects];
    if (!FIL_Ready()) return;
    NSMutableDictionary<NSNumber *, NSString *> *best = [NSMutableDictionary new];
    for (NSValue *v in FIL_FindAll("UnityEngine.UI", "Graphic")) {
        NSString *p = FIL_Path(v.pointerValue);
        NSRange r = [p rangeOfString:@"PlayerInfoNode/HeadTemplate_"];
        if (r.location == NSNotFound || !FIL_ActiveInHierarchy(v.pointerValue)) continue;
        int seat = [[p substringFromIndex:NSMaxRange(r)] intValue];
        if (seat < 1 || seat > 4) continue;
        if (!best[@(seat)] || p.length < best[@(seat)].length) { // ближе к корню — сам аватар
            if (self.seatHandles[@(seat)]) FIL_Unpin(self.seatHandles[@(seat)].unsignedIntValue);
            best[@(seat)] = p;
            self.seatHandles[@(seat)] = @(FIL_Pin(v.pointerValue));
        }
    }
}

- (BOOL)seat:(NSInteger)seat point:(CGPoint *)pt {
    [self refreshSeats];
    void *o = FIL_Target(self.seatHandles[@(seat)].unsignedIntValue);
    return o && FIL_ScreenPoint(o, pt);
}

- (UIView *)host { return [[FlideFX shared] overlayView]; }

- (CGPoint)myPoint {
    CGPoint p;
    NSString *me = [FDefaults() stringForKey:kMyAvatar];
    if (me && [[FlideEngine shared] screenPointForPath:me point:&p]) return p;
    if ([self seat:1 point:&p]) return p;
    UIView *h = [self host];
    return CGPointMake(h.bounds.size.width * 0.12, h.bounds.size.height * 0.72);
}

- (NSArray<NSValue *> *)opponentPoints {
    NSMutableArray *out = [NSMutableArray new];
    for (NSInteger s = 2; s <= 4; s++) { CGPoint p; if ([self seat:s point:&p]) [out addObject:[NSValue valueWithCGPoint:p]]; }
    return out;
}

#pragma mark - отрисовка

static UIImage *emojiImage(NSString *e, CGFloat size) {
    static NSCache *cache;
    if (!cache) cache = [NSCache new];
    NSString *key = [NSString stringWithFormat:@"%@%.0f", e, size];
    UIImage *img = [cache objectForKey:key];
    if (img) return img;
    img = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)] imageWithActions:^(UIGraphicsImageRendererContext *c) {
        NSDictionary *a = @{NSFontAttributeName: [UIFont systemFontOfSize:size * 0.82]};
        CGSize s = [e sizeWithAttributes:a];
        [e drawAtPoint:CGPointMake((size - s.width) / 2, (size - s.height) / 2) withAttributes:a];
    }];
    [cache setObject:img forKey:key];
    return img;
}

static UIImage *imageFor(id thing, CGFloat size) {
    if ([thing isKindOfClass:NSString.class] && [(NSString *)thing hasPrefix:@"/"])
        return FlideLoadImage(thing, size);
    if ([thing isKindOfClass:NSDictionary.class]) return emojiImage(thing[@"icon"], size);
    if ([thing isKindOfClass:NSString.class]) return emojiImage(thing, size);
    return nil;
}

// Пузырь как в игре: белое облачко с хвостиком к аватару, стикер внутри
- (UIView *)bubbleWith:(UIImage *)img tailLeft:(BOOL)tailLeft {
    CGFloat W = 78, H = 70, tail = 10;
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, H + tail)];
    CAShapeLayer *shape = [CAShapeLayer layer];
    UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, W, H) cornerRadius:16];
    UIBezierPath *t = [UIBezierPath bezierPath];
    CGFloat tx = tailLeft ? 16 : W - 16;
    [t moveToPoint:CGPointMake(tx - 8, H - 1)];
    [t addLineToPoint:CGPointMake(tx + (tailLeft ? -6 : 6), H + tail)];
    [t addLineToPoint:CGPointMake(tx + 8, H - 1)];
    [t closePath];
    [p appendPath:t];
    shape.path = p.CGPath;
    shape.fillColor = UIColor.whiteColor.CGColor;
    shape.strokeColor = [UIColor colorWithRed:0.35 green:0.55 blue:0.95 alpha:1].CGColor;
    shape.lineWidth = 2.5;
    shape.shadowColor = UIColor.blackColor.CGColor; shape.shadowOpacity = 0.35; shape.shadowRadius = 4; shape.shadowOffset = CGSizeMake(0, 2);
    [v.layer addSublayer:shape];
    UIImageView *iv = [[UIImageView alloc] initWithImage:img];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.frame = CGRectMake(8, 6, W - 16, H - 12);
    iv.tag = 7;
    [v addSubview:iv];
    return v;
}

- (void)sendEmote:(id)emote {
    UIView *h = [self host];
    UIImage *img = imageFor(emote, 140);
    if (!h || !img) return;
    [[FlideSound shared] play:@"emote"];
    CGPoint me = [self myPoint];
    BOOL right = me.x < h.bounds.size.width / 2;
    UIView *b = [self bubbleWith:img tailLeft:right];
    b.layer.anchorPoint = CGPointMake(right ? 0.15 : 0.85, 1);
    b.center = CGPointMake(me.x + (right ? 30 : -30), me.y - 26);
    b.transform = CGAffineTransformMakeScale(0.1, 0.1);
    b.alpha = 0;
    [h addSubview:b];
    UIView *sticker = [b viewWithTag:7];
    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.42 initialSpringVelocity:1.4 options:0 animations:^{
        b.transform = CGAffineTransformIdentity; b.alpha = 1;
    } completion:^(BOOL f) {
        // стикер «живёт»: подпрыгивает и качается
        CAKeyframeAnimation *hop = [CAKeyframeAnimation animationWithKeyPath:@"transform"];
        hop.values = @[[NSValue valueWithCATransform3D:CATransform3DIdentity],
                       [NSValue valueWithCATransform3D:CATransform3DConcat(CATransform3DMakeScale(1.12, 0.9, 1), CATransform3DMakeTranslation(0, 3, 0))],
                       [NSValue valueWithCATransform3D:CATransform3DConcat(CATransform3DMakeScale(0.92, 1.1, 1), CATransform3DMakeTranslation(0, -6, 0))],
                       [NSValue valueWithCATransform3D:CATransform3DMakeRotation(0.12, 0, 0, 1)],
                       [NSValue valueWithCATransform3D:CATransform3DMakeRotation(-0.12, 0, 0, 1)],
                       [NSValue valueWithCATransform3D:CATransform3DIdentity]];
        hop.duration = 0.9; hop.repeatCount = 2;
        [sticker.layer addAnimation:hop forKey:nil];
        [UIView animateWithDuration:0.35 delay:1.9 options:UIViewAnimationOptionCurveEaseIn animations:^{
            b.transform = CGAffineTransformMakeScale(0.2, 0.2); b.alpha = 0;
        } completion:^(BOOL f2) { [b removeFromSuperview]; }];
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
        double delay = i * 0.05, dur = 1.6 + drand48();
        [UIView animateWithDuration:dur delay:delay options:UIViewAnimationOptionCurveEaseIn animations:^{
            d.center = CGPointMake(d.center.x + (drand48() - 0.5) * 80, s.height + 60);
            d.transform = CGAffineTransformMakeRotation((drand48() - 0.5) * 4);
        } completion:^(BOOL f) { [d removeFromSuperview]; }];
    }
}

// брызги при попадании (как яйцо в игре)
- (void)splatAt:(CGPoint)p color:(UIColor *)color in:(UIView *)h {
    CAShapeLayer *blob = [CAShapeLayer layer];
    UIBezierPath *path = [UIBezierPath bezierPath];
    int spikes = 14;
    for (int i = 0; i <= spikes * 2; i++) {
        double a = (double)i / (spikes * 2) * M_PI * 2;
        double r = (i % 2 ? 18 : 30) + drand48() * 10;
        CGPoint q = CGPointMake(cos(a) * r, sin(a) * r);
        if (i == 0) [path moveToPoint:q]; else [path addLineToPoint:q];
    }
    [path closePath];
    blob.path = path.CGPath;
    blob.fillColor = color.CGColor;
    blob.position = p;
    blob.lineJoin = kCALineJoinRound;
    blob.strokeColor = [color colorWithAlphaComponent:0.6].CGColor;
    blob.lineWidth = 4;
    [h.layer addSublayer:blob];
    CAKeyframeAnimation *sc = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    sc.values = @[@0.1, @1.25, @1.0]; sc.keyTimes = @[@0, @0.25, @1]; sc.duration = 0.35;
    [blob addAnimation:sc forKey:nil];
    for (int i = 0; i < 9; i++) { // капли
        CALayer *d = [CALayer layer];
        CGFloat sz = 5 + drand48() * 7;
        d.bounds = CGRectMake(0, 0, sz, sz); d.cornerRadius = sz / 2;
        d.backgroundColor = color.CGColor;
        d.position = p;
        [h.layer addSublayer:d];
        double a = drand48() * M_PI * 2, dist = 40 + drand48() * 40;
        CABasicAnimation *mv = [CABasicAnimation animationWithKeyPath:@"position"];
        mv.toValue = [NSValue valueWithCGPoint:CGPointMake(p.x + cos(a) * dist, p.y + sin(a) * dist + 20)];
        mv.duration = 0.5; mv.fillMode = kCAFillModeForwards; mv.removedOnCompletion = NO;
        mv.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [d addAnimation:mv forKey:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [d removeFromSuperlayer]; });
    }
    // стекает и тает
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CABasicAnimation *drip = [CABasicAnimation animationWithKeyPath:@"transform"];
        drip.toValue = [NSValue valueWithCATransform3D:CATransform3DConcat(CATransform3DMakeScale(0.9, 1.4, 1), CATransform3DMakeTranslation(0, 18, 0))];
        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"]; fade.toValue = @0;
        CAAnimationGroup *g = [CAAnimationGroup animation];
        g.animations = @[drip, fade]; g.duration = 0.9; g.fillMode = kCAFillModeForwards; g.removedOnCompletion = NO;
        [blob addAnimation:g forKey:nil];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [blob removeFromSuperlayer]; });
}

- (void)sendGift:(id)gift toPoint:(NSValue *)target {
    UIView *h = [self host];
    UIImage *img = imageFor(gift, 160);
    if (!h || !img) return;
    [[FlideSound shared] play:@"gift"];
    CGPoint from = [self myPoint];
    CGPoint to = target ? target.CGPointValue : CGPointMake(from.x, from.y - 1);
    BOOL toSelf = !target;
    if (toSelf) from = CGPointMake(h.bounds.size.width / 2, h.bounds.size.height + 60);
    NSString *gid = [gift isKindOfClass:NSDictionary.class] ? gift[@"id"] : @"custom";

    UIImageView *iv = [[UIImageView alloc] initWithImage:img];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.frame = CGRectMake(0, 0, 64, 64);
    iv.center = from;
    iv.layer.shadowColor = UIColor.blackColor.CGColor;
    iv.layer.shadowRadius = 6; iv.layer.shadowOpacity = 0.5; iv.layer.shadowOffset = CGSizeMake(0, 6);
    [h addSubview:iv];

    // бросок по высокой дуге с вращением и тенью-«высотой»
    double dist = hypot(to.x - from.x, to.y - from.y);
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:from];
    [path addQuadCurveToPoint:to controlPoint:CGPointMake((from.x + to.x) / 2, MIN(from.y, to.y) - MAX(90, dist * 0.45))];
    CAKeyframeAnimation *fly = [CAKeyframeAnimation animationWithKeyPath:@"position"];
    fly.path = path.CGPath;
    fly.duration = 0.75;
    fly.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.3 :0.1 :0.6 :1];
    CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    spin.toValue = @(M_PI * ([gid isEqualToString:@"rocket"] ? 0 : 3)); spin.duration = 0.75;
    CAKeyframeAnimation *grow = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    grow.values = @[@0.7, @1.35, @1.0]; grow.duration = 0.75;
    iv.layer.position = to;
    [iv.layer addAnimation:fly forKey:nil];
    [iv.layer addAnimation:spin forKey:nil];
    [iv.layer addAnimation:grow forKey:nil];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        BOOL messy = [gid isEqualToString:@"egg"] || [gid isEqualToString:@"tomato"];
        if (messy) {
            UIColor *c = [gid isEqualToString:@"egg"] ? [UIColor colorWithRed:1 green:0.86 blue:0.25 alpha:0.95]
                                                      : [UIColor colorWithRed:0.9 green:0.15 blue:0.1 alpha:0.95];
            [iv removeFromSuperview];
            [self splatAt:to color:c in:h];
        } else if ([gid isEqualToString:@"bomb"]) {
            [iv removeFromSuperview];
            [[FlideFX shared] burstAt:to big:YES];
            [self splatAt:to color:[UIColor colorWithWhite:0.1 alpha:0.9] in:h];
            [[FlideFun shared] shakeScreen];
        } else {
            [[FlideFX shared] burstAt:to big:YES];
            if ([gid isEqualToString:@"fire"]) [[FlideFun shared] fireworksNow];
            else if ([gid isEqualToString:@"hearts"]) [self rain:emojiImage(@"💖", 60) count:26 in:h];
            else if ([gid isEqualToString:@"roses"]) [self rain:emojiImage(@"🌹", 60) count:22 in:h];
            else if ([gid isEqualToString:@"money"]) [self rain:emojiImage(@"💸", 60) count:32 in:h];
            else if ([gid isEqualToString:@"cup"] || [gid isEqualToString:@"crown"]) [[FlideFun shared] confettiNow];
            [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.4 initialSpringVelocity:1 options:0 animations:^{
                iv.transform = CGAffineTransformMakeScale(1.5, 1.5);
            } completion:^(BOOL f) {
                [UIView animateWithDuration:0.6 delay:1.2 options:0 animations:^{
                    iv.alpha = 0; iv.transform = CGAffineTransformMakeScale(0.3, 0.3);
                } completion:^(BOOL f2) { [iv removeFromSuperview]; }];
            }];
        }
        if (FBool(kFunHaptic)) [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy] impactOccurred];
    });
}

@end
