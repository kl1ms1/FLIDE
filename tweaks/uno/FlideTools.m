// FLIDE · инструменты: рисование поверх экрана, стикеры, чистый скриншот, клип последних 30 секунд.
#import "FlideCore.h"
#import <ReplayKit/ReplayKit.h>

#pragma mark - холст

@interface FlideCanvas : UIView
@property (nonatomic, strong) NSMutableArray<CAShapeLayer *> *strokes;
@property (nonatomic, strong) UIBezierPath *path;
@property (nonatomic, strong) CAShapeLayer *current;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, assign) CGFloat width;
@end

@implementation FlideCanvas
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        _strokes = [NSMutableArray new];
        _color = FlideColorFromHex([FDefaults() stringForKey:kFxColor]);
        _width = 6;
        self.backgroundColor = UIColor.clearColor;
        self.multipleTouchEnabled = NO;
    }
    return self;
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint p = [touches.anyObject locationInView:self];
    self.path = [UIBezierPath bezierPath];
    [self.path moveToPoint:p];
    self.current = [CAShapeLayer layer];
    self.current.strokeColor = self.color.CGColor;
    self.current.fillColor = UIColor.clearColor.CGColor;
    self.current.lineWidth = self.width;
    self.current.lineCap = kCALineCapRound;
    self.current.lineJoin = kCALineJoinRound;
    self.current.shadowColor = self.color.CGColor; self.current.shadowOpacity = 0.8; self.current.shadowRadius = 6; self.current.shadowOffset = CGSizeZero;
    [self.layer addSublayer:self.current];
    [self.strokes addObject:self.current];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.path addLineToPoint:[touches.anyObject locationInView:self]];
    self.current.path = self.path.CGPath;
}
- (void)undo { [self.strokes.lastObject removeFromSuperlayer]; [self.strokes removeLastObject]; }
- (void)clear { for (CALayer *l in self.strokes) [l removeFromSuperlayer]; [self.strokes removeAllObjects]; }
@end

#pragma mark - инструменты

@interface FlideTools ()
@property (nonatomic, strong) FlideCanvas *canvas;
@property (nonatomic, strong) UIView *toolbar;
@property (nonatomic, strong) NSMutableArray<UIView *> *stickers;
@end

@implementation FlideTools

+ (instancetype)shared {
    static FlideTools *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [FlideTools new]; s.stickers = [NSMutableArray new]; });
    return s;
}

#pragma mark рисование

- (UIButton *)toolButton:(NSString *)title action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:20];
    b.tintColor = UIColor.whiteColor;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)toggleDrawingIn:(UIView *)host {
    if (self.canvas && self.canvas.userInteractionEnabled) { [self finishDrawing]; return; }
    if (!self.canvas) {
        self.canvas = [[FlideCanvas alloc] initWithFrame:host.bounds];
        self.canvas.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [host insertSubview:self.canvas atIndex:0];
    }
    self.canvas.userInteractionEnabled = YES;

    UIView *bar = FlideGlass(22);
    NSArray *colors = @[UIColor.whiteColor, UIColor.systemRedColor, UIColor.systemYellowColor, UIColor.systemGreenColor,
                        UIColor.systemBlueColor, UIColor.systemPinkColor, FlideColorFromHex([FDefaults() stringForKey:kFxColor])];
    UIStackView *st = [UIStackView new];
    st.axis = UILayoutConstraintAxisHorizontal;
    st.spacing = 10;
    st.alignment = UIStackViewAlignmentCenter;
    for (NSUInteger i = 0; i < colors.count; i++) {
        UIButton *c = [UIButton buttonWithType:UIButtonTypeCustom];
        c.backgroundColor = colors[i];
        c.layer.cornerRadius = 13;
        c.layer.borderColor = UIColor.whiteColor.CGColor; c.layer.borderWidth = 1.5;
        c.tag = (NSInteger)i;
        [c.widthAnchor constraintEqualToConstant:26].active = YES;
        [c.heightAnchor constraintEqualToConstant:26].active = YES;
        [c addTarget:self action:@selector(pickColor:) forControlEvents:UIControlEventTouchUpInside];
        [st addArrangedSubview:c];
    }
    [st addArrangedSubview:[self toolButton:@"✏︎" action:@selector(thinner)]];
    [st addArrangedSubview:[self toolButton:@"🖌" action:@selector(thicker)]];
    [st addArrangedSubview:[self toolButton:@"↶" action:@selector(undo)]];
    [st addArrangedSubview:[self toolButton:@"🗑" action:@selector(clearDrawing)]];
    [st addArrangedSubview:[self toolButton:@"✓" action:@selector(finishDrawing)]];
    CGSize sz = [st systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    bar.frame = CGRectMake((host.bounds.size.width - sz.width - 28) / 2, host.safeAreaInsets.top + 8, sz.width + 28, 50);
    st.frame = CGRectMake(14, 0, sz.width, 50);
    UIView *content = [bar isKindOfClass:UIVisualEffectView.class] ? ((UIVisualEffectView *)bar).contentView : bar;
    [content addSubview:st];
    [host addSubview:bar];
    [self.toolbar removeFromSuperview];
    self.toolbar = bar;
}

- (void)pickColor:(UIButton *)b { self.canvas.color = b.backgroundColor; }
- (void)thinner { self.canvas.width = MAX(2, self.canvas.width - 3); }
- (void)thicker { self.canvas.width = MIN(30, self.canvas.width + 3); }
- (void)undo { [self.canvas undo]; }
- (void)clearDrawing { [self.canvas clear]; }

- (void)finishDrawing {
    // рисунок остаётся, но касания снова идут в игру
    self.canvas.userInteractionEnabled = NO;
    [self.toolbar removeFromSuperview];
    self.toolbar = nil;
    if (!self.canvas.strokes.count) { [self.canvas removeFromSuperview]; self.canvas = nil; }
}

#pragma mark стикеры

- (void)addSticker:(UIImage *)img in:(UIView *)host {
    UIImageView *iv = [[UIImageView alloc] initWithImage:img];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.frame = CGRectMake(0, 0, 110, 110);
    iv.center = CGPointMake(host.bounds.size.width / 2, host.bounds.size.height / 2);
    iv.userInteractionEnabled = YES;
    [iv addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)]];
    [iv addGestureRecognizer:[[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinch:)]];
    [iv addGestureRecognizer:[[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(rotate:)]];
    [iv addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(remove:)]];
    [host addSubview:iv];
    [self.stickers addObject:iv];
    iv.transform = CGAffineTransformMakeScale(0.2, 0.2);
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:1 options:0 animations:^{
        iv.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)pan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:g.view.superview];
    g.view.center = CGPointMake(g.view.center.x + t.x, g.view.center.y + t.y);
    [g setTranslation:CGPointZero inView:g.view.superview];
}
- (void)pinch:(UIPinchGestureRecognizer *)g { g.view.transform = CGAffineTransformScale(g.view.transform, g.scale, g.scale); g.scale = 1; }
- (void)rotate:(UIRotationGestureRecognizer *)g { g.view.transform = CGAffineTransformRotate(g.view.transform, g.rotation); g.rotation = 0; }
- (void)remove:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    UIView *v = g.view;
    [UIView animateWithDuration:0.25 animations:^{ v.alpha = 0; v.transform = CGAffineTransformScale(v.transform, 0.1, 0.1); }
                     completion:^(BOOL f) { [v removeFromSuperview]; }];
    [self.stickers removeObject:v];
}
- (void)clearAll {
    [self clearStickers];
    [self.canvas clear];
    [self.canvas removeFromSuperview];
    self.canvas = nil;
    [self.toolbar removeFromSuperview];
    self.toolbar = nil;
}

- (void)clearStickers { for (UIView *v in self.stickers) [v removeFromSuperview]; [self.stickers removeAllObjects]; }

#pragma mark скриншот

- (UIImage *)cleanScreenshot {
    // кадр прямо из Unity — без окон FLIDE и без системных оверлеев
    UIImage *img = nil;
    if (FIL_Ready()) {
        void *tex = FIL_Static("UnityEngine", "ScreenCapture", "CaptureScreenshotAsTexture", 0, NULL);
        if (tex) {
            img = [[FlideEngine shared] imageOfTextureObject:tex maxSide:4096];
            void *a[1] = { tex };
            FIL_Static("UnityEngine", "Object", "Destroy", 1, a);
        }
    }
    if (!img) { // запасной вариант — снимок окна игры
        UIWindow *game = nil;
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes)
            if ([sc isKindOfClass:UIWindowScene.class])
                for (UIWindow *w in ((UIWindowScene *)sc).windows)
                    if (![FlideMenu isOverlayWindow:w] && w.rootViewController && w.userInteractionEnabled) { game = w; break; }
        if (game) img = [[[UIGraphicsImageRenderer alloc] initWithBounds:game.bounds] imageWithActions:^(UIGraphicsImageRendererContext *c) {
            [game drawViewHierarchyInRect:game.bounds afterScreenUpdates:NO];
        }];
    }
    if (img) {
        NSDateFormatter *df = [NSDateFormatter new];
        df.dateFormat = @"yyyy-MM-dd_HH-mm-ss";
        NSString *path = [FlideDir(@"shots") stringByAppendingPathComponent:[NSString stringWithFormat:@"UNO_%@.png", [df stringFromDate:NSDate.date]]];
        [UIImagePNGRepresentation(img) writeToFile:path atomically:YES];
    }
    return img;
}

#pragma mark клипы

- (BOOL)clipBuffering {
    if (@available(iOS 15.0, *)) return RPScreenRecorder.sharedRecorder.isRecording;
    return NO;
}

- (void)setClipBuffering:(BOOL)on completion:(void (^)(NSError *))done {
    if (@available(iOS 15.0, *)) {
        RPScreenRecorder *r = RPScreenRecorder.sharedRecorder;
        void (^fin)(NSError *) = ^(NSError *e) { dispatch_async(dispatch_get_main_queue(), ^{ if (done) done(e); }); };
        if (on) [r startClipBufferingWithCompletionHandler:fin];
        else [r stopClipBufferingWithCompletionHandler:fin];
    } else if (done) done([NSError errorWithDomain:@"FLIDE" code:1 userInfo:@{NSLocalizedDescriptionKey: L(@"Нужна iOS 15+")}]);
}

- (void)exportClip:(void (^)(NSURL *, NSError *))done {
    if (@available(iOS 15.0, *)) {
        NSDateFormatter *df = [NSDateFormatter new];
        df.dateFormat = @"yyyy-MM-dd_HH-mm-ss";
        NSURL *url = [NSURL fileURLWithPath:[FlideDir(@"clips") stringByAppendingPathComponent:
                                             [NSString stringWithFormat:@"UNO_%@.mp4", [df stringFromDate:NSDate.date]]]];
        [RPScreenRecorder.sharedRecorder exportClipToURL:url duration:30 completionHandler:^(NSError *e) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(e ? nil : url, e); });
        }];
    } else done(nil, [NSError errorWithDomain:@"FLIDE" code:1 userInfo:@{NSLocalizedDescriptionKey: L(@"Нужна iOS 15+")}]);
}

@end
