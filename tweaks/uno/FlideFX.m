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
        case FlideFxAura:      return L(@"✨ Аура");
        case FlideFxShadow:    return L(@"🌑 Тень");
        case FlideFxFire:      return L(@"🔥 Огонь");
        case FlideFxStars:     return L(@"⭐️ Звёзды");
        case FlideFxRunes:     return L(@"🔮 Руны");
        case FlideFxGalaxy:    return L(@"🌌 Галактика");
        case FlideFxLightning: return L(@"⚡️ Молнии");
        case FlideFxSakura:    return L(@"🌸 Сакура");
        case FlideFxSnow:      return L(@"❄️ Снег");
        case FlideFxBubbles:   return L(@"🫧 Пузыри");
        case FlideFxHalo:      return L(@"😇 Нимб");
        case FlideFxHearts:    return L(@"💖 Сердца");
        case FlideFxNeon:      return L(@"🌈 Неон");
        case FlideFxVoid:      return L(@"🕳 Чёрная дыра");
        default:               return @"?";
    }
}

#pragma mark - картинки частиц (кэшируются — рисуем один раз)

static NSMutableDictionary<NSString *, UIImage *> *gSprites;

static UIImage *sprite(NSString *key, CGSize size, void (^draw)(CGContextRef c, CGSize s)) {
    if (!gSprites) gSprites = [NSMutableDictionary new];
    UIImage *img = gSprites[key];
    if (img) return img;
    img = [[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        draw(ctx.CGContext, size);
    }];
    gSprites[key] = img;
    return img;
}

static UIImage *dotImage(void) {
    return sprite(@"dot", CGSizeMake(32, 32), ^(CGContextRef c, CGSize s) {
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGFloat comps[] = { 1, 1, 1, 1,  1, 1, 1, 0.35,  1, 1, 1, 0 };
        CGFloat locs[] = { 0, 0.35, 1 };
        CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, locs, 3);
        CGContextDrawRadialGradient(c, g, CGPointMake(16, 16), 0, CGPointMake(16, 16), 16, 0);
        CGGradientRelease(g); CGColorSpaceRelease(cs);
    });
}

static UIImage *glyphImage(NSString *glyph, CGFloat size) {
    return sprite([@"g" stringByAppendingString:glyph], CGSizeMake(size, size), ^(CGContextRef c, CGSize s) {
        NSDictionary *attr = @{ NSFontAttributeName: [UIFont systemFontOfSize:size * 0.8 weight:UIFontWeightBold],
                                NSForegroundColorAttributeName: UIColor.whiteColor };
        CGSize gs = [glyph sizeWithAttributes:attr];
        [glyph drawAtPoint:CGPointMake((size - gs.width) / 2, (size - gs.height) / 2) withAttributes:attr];
    });
}

static UIImage *emojiSprite(NSString *e, CGFloat size) {
    return sprite([@"e" stringByAppendingString:e], CGSizeMake(size, size), ^(CGContextRef c, CGSize s) {
        NSDictionary *attr = @{ NSFontAttributeName: [UIFont systemFontOfSize:size * 0.8] };
        CGSize gs = [e sizeWithAttributes:attr];
        [e drawAtPoint:CGPointMake((size - gs.width) / 2, (size - gs.height) / 2) withAttributes:attr];
    });
}

static UIImage *petalImage(void) {
    return sprite(@"petal", CGSizeMake(24, 24), ^(CGContextRef c, CGSize s) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        [p moveToPoint:CGPointMake(12, 2)];
        [p addQuadCurveToPoint:CGPointMake(12, 22) controlPoint:CGPointMake(24, 10)];
        [p addQuadCurveToPoint:CGPointMake(12, 2) controlPoint:CGPointMake(0, 10)];
        [UIColor.whiteColor setFill];
        [p fill];
    });
}

static UIImage *ringImage(void) {
    return sprite(@"ring", CGSizeMake(32, 32), ^(CGContextRef c, CGSize s) {
        CGContextSetStrokeColorWithColor(c, UIColor.whiteColor.CGColor);
        CGContextSetLineWidth(c, 2);
        CGContextStrokeEllipseInRect(c, CGRectMake(3, 3, 26, 26));
        CGContextSetFillColorWithColor(c, [UIColor colorWithWhite:1 alpha:0.6].CGColor);
        CGContextFillEllipseInRect(c, CGRectMake(9, 7, 6, 4));
    });
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

#pragma mark - строительные блоки

static CABasicAnimation *spinAnim(double dur, BOOL reverse) {
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    a.toValue = @(reverse ? -M_PI * 2 : M_PI * 2); a.duration = dur; a.repeatCount = HUGE_VALF;
    return a;
}

// мягкое пульсирующее свечение — основа почти каждого эффекта
static CALayer *glow(UIColor *color, CGFloat r, CGFloat alpha) {
    CAGradientLayer *g = [CAGradientLayer layer];
    g.type = kCAGradientLayerRadial;
    g.frame = CGRectMake(0, 0, r * 2, r * 2);
    g.colors = @[(id)[color colorWithAlphaComponent:alpha].CGColor, (id)[color colorWithAlphaComponent:alpha * 0.35].CGColor, (id)UIColor.clearColor.CGColor];
    g.locations = @[@0, @0.45, @1];
    g.startPoint = CGPointMake(0.5, 0.5); g.endPoint = CGPointMake(1, 1);
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    pulse.fromValue = @0.88; pulse.toValue = @1.08; pulse.duration = 1.2; pulse.autoreverses = YES; pulse.repeatCount = HUGE_VALF;
    pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [g addAnimation:pulse forKey:@"pulse"];
    return g;
}

// кольцо с градиентной обводкой (conic), вращается
static CALayer *gradientRing(NSArray<UIColor *> *colors, CGFloat r, CGFloat width, double spin, BOOL dashed) {
    CAGradientLayer *g = [CAGradientLayer layer];
    g.type = kCAGradientLayerConic;
    g.frame = CGRectMake(0, 0, r * 2, r * 2);
    NSMutableArray *cg = [NSMutableArray new];
    for (UIColor *c in colors) [cg addObject:(id)c.CGColor];
    [cg addObject:(id)colors.firstObject.CGColor];
    g.colors = cg;
    g.startPoint = CGPointMake(0.5, 0.5); g.endPoint = CGPointMake(0.5, 0);
    CAShapeLayer *m = [CAShapeLayer layer];
    m.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(g.bounds, width, width)].CGPath;
    m.fillColor = UIColor.clearColor.CGColor;
    m.strokeColor = UIColor.blackColor.CGColor;
    m.lineWidth = width;
    m.lineCap = kCALineCapRound;
    if (dashed) m.lineDashPattern = @[@(width * 0.5), @(width * 2.2)];
    g.mask = m;
    g.shadowColor = colors.firstObject.CGColor; g.shadowOpacity = 1; g.shadowRadius = width * 1.5; g.shadowOffset = CGSizeZero;
    if (spin > 0) [g addAnimation:spinAnim(spin, NO) forKey:@"spin"];
    return g;
}

static CAEmitterLayer *emitter(CGFloat r, NSString *shape, NSString *mode) {
    CAEmitterLayer *em = [CAEmitterLayer layer];
    em.frame = CGRectMake(0, 0, r * 2, r * 2);
    em.emitterPosition = CGPointMake(r, r);
    em.emitterSize = CGSizeMake(r * 1.5, r * 1.5);
    em.emitterShape = shape;
    em.emitterMode = mode;
    em.renderMode = kCAEmitterLayerAdditive;
    return em;
}

static void center(CALayer *l, CGFloat r) { l.position = CGPointMake(r, r); }

// заранее сгенерированные молнии, переключаются ключевыми кадрами — без таймеров
static CALayer *lightning(UIColor *color, CGFloat r) {
    CAShapeLayer *bolt = [CAShapeLayer layer];
    bolt.frame = CGRectMake(0, 0, r * 2, r * 2);
    bolt.strokeColor = UIColor.whiteColor.CGColor;
    bolt.fillColor = UIColor.clearColor.CGColor;
    bolt.lineWidth = 2;
    bolt.lineJoin = kCALineJoinBevel;
    bolt.shadowColor = color.CGColor; bolt.shadowOpacity = 1; bolt.shadowRadius = 6; bolt.shadowOffset = CGSizeZero;
    NSMutableArray *paths = [NSMutableArray new];
    for (int f = 0; f < 8; f++) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        int arcs = 2 + f % 2;
        for (int a = 0; a < arcs; a++) {
            double ang = drand48() * M_PI * 2;
            CGPoint pt = CGPointMake(r + cos(ang) * r * 0.3, r + sin(ang) * r * 0.3);
            [p moveToPoint:pt];
            for (int k = 1; k <= 5; k++) {
                double rr = r * (0.3 + 0.14 * k);
                double aa = ang + (drand48() - 0.5) * 0.6;
                [p addLineToPoint:CGPointMake(r + cos(aa) * rr, r + sin(aa) * rr)];
            }
        }
        [paths addObject:(id)p.CGPath];
    }
    CAKeyframeAnimation *k = [CAKeyframeAnimation animationWithKeyPath:@"path"];
    k.values = paths; k.calculationMode = kCAAnimationDiscrete; k.duration = 0.64; k.repeatCount = HUGE_VALF;
    [bolt addAnimation:k forKey:@"bolt"];
    CAKeyframeAnimation *flick = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    flick.values = @[@1, @0.2, @1, @0.6, @1, @0]; flick.duration = 0.64; flick.repeatCount = HUGE_VALF;
    [bolt addAnimation:flick forKey:@"flick"];
    return bolt;
}

// руны по кругу, медленно вращаются
static CALayer *runeCircle(UIColor *color, CGFloat r) {
    CALayer *ring = [CALayer layer];
    ring.frame = CGRectMake(0, 0, r * 2, r * 2);
    NSArray *runes = @[@"ᚠ", @"ᚱ", @"ᚨ", @"ᛟ", @"ᛉ", @"ᚦ", @"ᛗ", @"ᛞ"];
    for (NSUInteger i = 0; i < runes.count; i++) {
        CATextLayer *t = [CATextLayer layer];
        t.string = runes[i];
        t.fontSize = r * 0.28;
        t.foregroundColor = UIColor.whiteColor.CGColor;
        t.alignmentMode = kCAAlignmentCenter;
        t.contentsScale = UIScreen.mainScreen.scale;
        t.bounds = CGRectMake(0, 0, r * 0.4, r * 0.4);
        double a = (double)i / runes.count * M_PI * 2;
        t.position = CGPointMake(r + cos(a) * r * 0.82, r + sin(a) * r * 0.82);
        t.transform = CATransform3DMakeRotation(a + M_PI_2, 0, 0, 1);
        t.shadowColor = color.CGColor; t.shadowOpacity = 1; t.shadowRadius = 5; t.shadowOffset = CGSizeZero;
        [ring addSublayer:t];
    }
    [ring addAnimation:spinAnim(9, NO) forKey:@"spin"];
    return ring;
}

#pragma mark - сборка эффекта

static UIColor *shifted(UIColor *c, CGFloat dh) {
    CGFloat h, s, b, a;
    [c getHue:&h saturation:&s brightness:&b alpha:&a];
    return [UIColor colorWithHue:fmod(h + dh + 1, 1) saturation:s brightness:b alpha:a];
}

static CALayer *makeEffect(FlideFxStyle style, UIColor *color, CGFloat radius) {
    CGFloat r = radius;
    CALayer *root = [CALayer layer];
    root.bounds = CGRectMake(0, 0, r * 2, r * 2);
    CAEmitterLayer *em = nil;   // главный излучатель — первым слоем (burstAt его ищет)

    switch (style) {
        case FlideFxAura: {
            em = emitter(r, kCAEmitterLayerCircle, kCAEmitterLayerOutline);
            CAEmitterCell *c = cell(dotImage(), color, 50, 1.8, 14, 0.25);
            c.yAcceleration = -50;
            CAEmitterCell *s = cell(glyphImage(@"✦", 24), UIColor.whiteColor, 8, 1.3, 10, 0.45);
            s.yAcceleration = -35; s.spinRange = 3;
            em.emitterCells = @[c, s];
            [root addSublayer:glow(color, r, 0.45)];
            CALayer *ring = gradientRing(@[color, shifted(color, 0.1), [color colorWithAlphaComponent:0.1]], r * 0.92, 2.5, 5, YES);
            center(ring, r); [root addSublayer:ring];
            break;
        }
        case FlideFxShadow: {
            em = emitter(r, kCAEmitterLayerCircle, kCAEmitterLayerOutline);
            em.renderMode = kCAEmitterLayerOldestFirst;
            CAEmitterCell *c = cell(dotImage(), [UIColor colorWithRed:0.08 green:0.02 blue:0.12 alpha:0.6], 34, 2.4, 10, 1.0);
            c.yAcceleration = -14; c.alphaSpeed = -0.3;
            em.emitterCells = @[c];
            [root addSublayer:glow([UIColor colorWithRed:0.35 green:0.1 blue:0.6 alpha:1], r, 0.5)];
            CAReplicatorLayer *rep = [CAReplicatorLayer layer];
            rep.frame = root.bounds;
            rep.instanceCount = 3;
            rep.instanceTransform = CATransform3DMakeRotation(M_PI * 2 / 3, 0, 0, 1);
            CALayer *orb = [CALayer layer];
            orb.bounds = CGRectMake(0, 0, 14, 14);
            orb.cornerRadius = 7;
            orb.backgroundColor = UIColor.blackColor.CGColor;
            orb.borderColor = color.CGColor; orb.borderWidth = 1.5;
            orb.shadowColor = color.CGColor; orb.shadowOpacity = 1; orb.shadowRadius = 10; orb.shadowOffset = CGSizeZero;
            orb.position = CGPointMake(r, r * 0.12);
            CAEmitterLayer *tail = [CAEmitterLayer layer];
            tail.emitterPosition = CGPointMake(7, 7); tail.emitterSize = CGSizeMake(2, 2);
            tail.renderMode = kCAEmitterLayerAdditive;
            CAEmitterCell *tc = cell(dotImage(), color, 40, 0.5, 2, 0.18);
            tail.emitterCells = @[tc];
            [orb addSublayer:tail];
            [rep addSublayer:orb];
            [rep addAnimation:spinAnim(2.2, NO) forKey:@"spin"];
            [root addSublayer:rep];
            break;
        }
        case FlideFxFire: {
            em = emitter(r, kCAEmitterLayerLine, kCAEmitterLayerVolume);
            em.emitterPosition = CGPointMake(r, r * 1.55);
            em.emitterSize = CGSizeMake(r * 1.3, 1);
            UIColor *core = [UIColor colorWithRed:1 green:0.85 blue:0.3 alpha:1];
            UIColor *mid = [UIColor colorWithRed:1 green:0.42 blue:0.08 alpha:1];
            CAEmitterCell *a = cell(dotImage(), core, 70, 0.7, 40, 0.45);
            a.emissionLongitude = -M_PI_2; a.emissionRange = 0.35; a.yAcceleration = -140;
            CAEmitterCell *b = cell(dotImage(), mid, 90, 1.0, 30, 0.7);
            b.emissionLongitude = -M_PI_2; b.emissionRange = 0.5; b.yAcceleration = -110;
            CAEmitterCell *ember = cell(dotImage(), color, 12, 1.8, 60, 0.08);
            ember.emissionLongitude = -M_PI_2; ember.emissionRange = 0.8; ember.yAcceleration = -60;
            em.emitterCells = @[b, a, ember];
            CALayer *g = glow(mid, r, 0.5); [root addSublayer:g];
            break;
        }
        case FlideFxStars: {
            em = emitter(r, kCAEmitterLayerCircle, kCAEmitterLayerOutline);
            CAEmitterCell *c = cell(glyphImage(@"★", 28), color, 14, 1.4, 20, 0.45);
            c.spinRange = 4; c.alphaRange = 0.5;
            CAEmitterCell *d = cell(dotImage(), UIColor.whiteColor, 34, 0.8, 8, 0.12);
            em.emitterCells = @[c, d];
            [root addSublayer:glow(color, r, 0.3)];
            CAReplicatorLayer *rep = [CAReplicatorLayer layer];
            rep.frame = root.bounds; rep.instanceCount = 5;
            rep.instanceTransform = CATransform3DMakeRotation(M_PI * 2 / 5, 0, 0, 1);
            CATextLayer *st = [CATextLayer layer];
            st.string = @"★"; st.fontSize = 14; st.foregroundColor = UIColor.whiteColor.CGColor;
            st.contentsScale = UIScreen.mainScreen.scale; st.alignmentMode = kCAAlignmentCenter;
            st.bounds = CGRectMake(0, 0, 16, 18); st.position = CGPointMake(r, r * 0.1);
            st.shadowColor = color.CGColor; st.shadowOpacity = 1; st.shadowRadius = 6; st.shadowOffset = CGSizeZero;
            [rep addSublayer:st];
            [rep addAnimation:spinAnim(6, YES) forKey:@"spin"];
            [root addSublayer:rep];
            break;
        }
        case FlideFxRunes: {
            em = emitter(r, kCAEmitterLayerCircle, kCAEmitterLayerOutline);
            NSMutableArray *cells = [NSMutableArray new];
            for (NSString *rn in @[@"ᚠ", @"ᚱ", @"ᛟ", @"ᛉ"]) {
                CAEmitterCell *c = cell(glyphImage(rn, 28), color, 2, 2.0, 12, 0.45);
                c.yAcceleration = -25; c.spinRange = 1.2;
                [cells addObject:c];
            }
            em.emitterCells = cells;
            [root addSublayer:glow(color, r, 0.4)];
            CALayer *rc = runeCircle(color, r); [root addSublayer:rc];
            CALayer *ring = gradientRing(@[color, shifted(color, 0.15)], r * 0.62, 1.5, 4, NO);
            center(ring, r); [root addSublayer:ring];
            break;
        }
        case FlideFxGalaxy: {
            CAGradientLayer *disc = [CAGradientLayer layer];
            disc.type = kCAGradientLayerConic;
            disc.frame = root.bounds;
            disc.colors = @[(id)color.CGColor, (id)[UIColor colorWithRed:0.2 green:0.05 blue:0.4 alpha:0.2].CGColor,
                            (id)shifted(color, 0.3).CGColor, (id)UIColor.clearColor.CGColor, (id)color.CGColor];
            disc.startPoint = CGPointMake(0.5, 0.5); disc.endPoint = CGPointMake(0.5, 0);
            CAGradientLayer *mask = [CAGradientLayer layer];
            mask.type = kCAGradientLayerRadial; mask.frame = disc.bounds;
            mask.colors = @[(id)[UIColor colorWithWhite:0 alpha:0.9].CGColor, (id)UIColor.clearColor.CGColor];
            mask.startPoint = CGPointMake(0.5, 0.5); mask.endPoint = CGPointMake(1, 1);
            disc.mask = mask;
            [disc addAnimation:spinAnim(5, NO) forKey:@"spin"];
            [root addSublayer:disc];
            em = emitter(r, kCAEmitterLayerCircle, kCAEmitterLayerVolume);
            em.emitterSize = CGSizeMake(r * 1.8, r * 1.8);
            CAEmitterCell *s = cell(dotImage(), UIColor.whiteColor, 40, 1.2, 4, 0.1);
            s.alphaRange = 0.8;
            CAEmitterCell *s2 = cell(glyphImage(@"✦", 20), shifted(color, 0.5), 6, 1.4, 6, 0.35);
            s2.spin = 2;
            em.emitterCells = @[s, s2];
            break;
        }
        case FlideFxLightning: {
            [root addSublayer:glow(color, r, 0.4)];
            CALayer *b1 = lightning(color, r); [root addSublayer:b1];
            CALayer *b2 = lightning(shifted(color, 0.08), r); b2.transform = CATransform3DMakeRotation(1.3, 0, 0, 1); [root addSublayer:b2];
            em = emitter(r, kCAEmitterLayerCircle, kCAEmitterLayerOutline);
            CAEmitterCell *sp = cell(dotImage(), UIColor.whiteColor, 30, 0.4, 50, 0.1);
            em.emitterCells = @[sp];
            break;
        }
        case FlideFxSakura: {
            em = emitter(r, kCAEmitterLayerCircle, kCAEmitterLayerOutline);
            em.renderMode = kCAEmitterLayerUnordered;
            UIColor *pink = [UIColor colorWithRed:1 green:0.72 blue:0.82 alpha:1];
            CAEmitterCell *p = cell(petalImage(), pink, 14, 2.6, 18, 0.55);
            p.yAcceleration = 25; p.spin = 1.5; p.spinRange = 3; p.alphaSpeed = -0.3;
            CAEmitterCell *p2 = cell(petalImage(), UIColor.whiteColor, 6, 2.6, 14, 0.4);
            p2.yAcceleration = 20; p2.spinRange = 4; p2.alphaSpeed = -0.3;
            em.emitterCells = @[p, p2];
            [root addSublayer:glow(pink, r, 0.3)];
            break;
        }
        case FlideFxSnow: {
            em = emitter(r, kCAEmitterLayerCircle, kCAEmitterLayerVolume);
            em.renderMode = kCAEmitterLayerUnordered;
            CAEmitterCell *f = cell(glyphImage(@"❄", 24), [UIColor colorWithRed:0.85 green:0.95 blue:1 alpha:1], 12, 2.4, 10, 0.5);
            f.yAcceleration = 18; f.spinRange = 1.5; f.alphaSpeed = -0.35;
            CAEmitterCell *d = cell(dotImage(), UIColor.whiteColor, 30, 2, 6, 0.1);
            d.yAcceleration = 12;
            em.emitterCells = @[f, d];
            [root addSublayer:glow([UIColor colorWithRed:0.6 green:0.85 blue:1 alpha:1], r, 0.35)];
            CALayer *ring = gradientRing(@[UIColor.whiteColor, [UIColor colorWithRed:0.6 green:0.85 blue:1 alpha:1]], r * 0.85, 1.5, 7, YES);
            center(ring, r); [root addSublayer:ring];
            break;
        }
        case FlideFxBubbles: {
            em = emitter(r, kCAEmitterLayerLine, kCAEmitterLayerVolume);
            em.emitterPosition = CGPointMake(r, r * 1.6); em.emitterSize = CGSizeMake(r * 1.4, 1);
            em.renderMode = kCAEmitterLayerUnordered;
            CAEmitterCell *b = cell(ringImage(), color, 10, 2.4, 25, 0.6);
            b.emissionLongitude = -M_PI_2; b.emissionRange = 0.5; b.yAcceleration = -30; b.xAcceleration = 4;
            b.scaleSpeed = 0.1; b.alphaSpeed = -0.3;
            em.emitterCells = @[b];
            [root addSublayer:glow(color, r, 0.25)];
            break;
        }
        case FlideFxHalo: {
            UIColor *gold = [UIColor colorWithRed:1 green:0.85 blue:0.35 alpha:1];
            [root addSublayer:glow(gold, r, 0.35)];
            CALayer *ring = gradientRing(@[gold, UIColor.whiteColor, gold], r * 0.55, 4, 3, NO);
            ring.position = CGPointMake(r, r * 0.25);
            ring.transform = CATransform3DMakeScale(1, 0.32, 1);
            [root addSublayer:ring];
            em = emitter(r, kCAEmitterLayerCircle, kCAEmitterLayerOutline);
            em.emitterPosition = CGPointMake(r, r * 0.25); em.emitterSize = CGSizeMake(r * 1.1, r * 0.35);
            CAEmitterCell *s = cell(glyphImage(@"✧", 22), gold, 8, 1.4, 8, 0.4);
            s.yAcceleration = 20;
            em.emitterCells = @[s];
            break;
        }
        case FlideFxHearts: {
            em = emitter(r, kCAEmitterLayerCircle, kCAEmitterLayerOutline);
            em.renderMode = kCAEmitterLayerUnordered;
            CAEmitterCell *h = cell(emojiSprite(@"💖", 32), UIColor.whiteColor, 6, 1.8, 16, 0.5);
            h.yAcceleration = -40; h.spinRange = 0.8;
            CAEmitterCell *d = cell(dotImage(), [UIColor colorWithRed:1 green:0.4 blue:0.65 alpha:1], 30, 1.2, 10, 0.15);
            d.yAcceleration = -30;
            em.emitterCells = @[h, d];
            [root addSublayer:glow([UIColor colorWithRed:1 green:0.35 blue:0.6 alpha:1], r, 0.4)];
            break;
        }
        case FlideFxNeon: {
            NSArray *rainbow = @[UIColor.systemPinkColor, UIColor.systemPurpleColor, UIColor.systemBlueColor,
                                 UIColor.systemTealColor, UIColor.systemGreenColor, UIColor.systemYellowColor, UIColor.systemOrangeColor];
            CALayer *outer = gradientRing(rainbow, r * 0.95, 4, 2.5, NO); center(outer, r); [root addSublayer:outer];
            CALayer *inner = gradientRing(rainbow.reverseObjectEnumerator.allObjects, r * 0.75, 2, 0, YES); center(inner, r);
            [inner addAnimation:spinAnim(3.5, YES) forKey:@"spin"];
            [root addSublayer:inner];
            em = emitter(r, kCAEmitterLayerCircle, kCAEmitterLayerOutline);
            em.emitterSize = CGSizeMake(r * 1.9, r * 1.9);
            CAEmitterCell *sp = cell(dotImage(), UIColor.whiteColor, 30, 0.8, 12, 0.12);
            sp.color = UIColor.whiteColor.CGColor; sp.redRange = 1; sp.greenRange = 1; sp.blueRange = 1;
            em.emitterCells = @[sp];
            break;
        }
        case FlideFxVoid:
        default: {
            UIColor *acc = [UIColor colorWithRed:1 green:0.55 blue:0.15 alpha:1];
            CALayer *disk = gradientRing(@[acc, [UIColor colorWithRed:1 green:0.9 blue:0.6 alpha:1], [acc colorWithAlphaComponent:0.2]], r * 0.8, 6, 1.6, NO);
            center(disk, r); disk.transform = CATransform3DMakeScale(1, 0.45, 1);
            [root addSublayer:disk];
            CALayer *hole = [CALayer layer];
            hole.bounds = CGRectMake(0, 0, r * 0.7, r * 0.7);
            hole.cornerRadius = r * 0.35;
            hole.backgroundColor = UIColor.blackColor.CGColor;
            hole.shadowColor = acc.CGColor; hole.shadowOpacity = 1; hole.shadowRadius = 12; hole.shadowOffset = CGSizeZero;
            center(hole, r);
            [root addSublayer:hole];
            em = emitter(r, kCAEmitterLayerCircle, kCAEmitterLayerOutline);
            em.emitterSize = CGSizeMake(r * 1.9, r * 1.9);
            CAEmitterCell *d = cell(dotImage(), acc, 30, 1.0, -30, 0.12); // летят внутрь
            em.emitterCells = @[d];
            break;
        }
    }
    if (em) [root insertSublayer:em atIndex:0];
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
    BOOL sparks = FBool(kFxTouch), trail = FBool(kFunTrail) || FBool(kFunParty);
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
    self.link.preferredFramesPerSecond = 20;
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
    self.link.paused = self.auras.count == 0; // нет аур — ни одного кадра работы
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
    FlideFxStyle style = FBool(kFxRandom) ? (FlideFxStyle)arc4random_uniform(FlideFxStyleCount) : [FDefaults() integerForKey:kFxStyle];
    if (FBool(kFxRandom)) color = [UIColor colorWithHue:drand48() saturation:0.8 brightness:1 alpha:1];
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
