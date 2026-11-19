// FLIDE · быстрая панель на столе: эмоции и подарки в один тап, как в самой игре.
// Кнопка ✦😀 висит сбоку (перетаскивается). Эмоции: 8 своих слотов, удержи слот — поменять.
// Подарки: выбрал подарок → над соперниками появились цели → тапнул — бросок.
// Всё локально: видишь только ты.
#import "FlideCore.h"
#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>

static NSString *const kQuickPos = @"flide.quick.pos";

@interface FlideQuick () <PHPickerViewControllerDelegate>
@property (nonatomic, strong) UIButton *fab;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) NSMutableArray<UIView *> *targets;
@property (nonatomic, assign) NSInteger editingSlot;
@property (nonatomic, assign) NSInteger tab;
@end

@implementation FlideQuick

+ (instancetype)shared {
    static FlideQuick *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [FlideQuick new]; s.targets = [NSMutableArray new]; });
    return s;
}

- (UIView *)root { return [FlideMenu overlayRoot]; }

- (void)refresh {
    BOOL on = [FDefaults() objectForKey:kQuickBar] ? FBool(kQuickBar) : YES;
    UIView *root = [self root];
    if (!on || !root) { [self.fab removeFromSuperview]; self.fab = nil; [self closePanel]; return; }
    if (self.fab) { [root bringSubviewToFront:self.fab]; return; }

    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(0, 0, 50, 50);
    UIView *g = FlideGlass(25);
    g.frame = b.bounds;
    g.userInteractionEnabled = NO;
    [b addSubview:g];
    UILabel *l = [[UILabel alloc] initWithFrame:b.bounds];
    l.text = @"😀";
    l.font = [UIFont systemFontOfSize:26];
    l.textAlignment = NSTextAlignmentCenter;
    l.userInteractionEnabled = NO;
    [b addSubview:l];
    b.layer.shadowColor = FlideAccent().CGColor; b.layer.shadowOpacity = 0.8; b.layer.shadowRadius = 10; b.layer.shadowOffset = CGSizeZero;
    NSArray *pos = [FDefaults() arrayForKey:kQuickPos];
    b.center = pos.count == 2 ? CGPointMake([pos[0] doubleValue], [pos[1] doubleValue])
                              : CGPointMake(root.safeAreaInsets.left + 40, root.bounds.size.height * 0.55);
    [b addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [b addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
    [root addSubview:b];
    self.fab = b;
    // мягкое «дыхание», чтобы кнопку было видно
    CABasicAnimation *br = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    br.fromValue = @1.0; br.toValue = @1.07; br.duration = 1.4; br.autoreverses = YES; br.repeatCount = HUGE_VALF;
    [b.layer addAnimation:br forKey:@"breath"];
}

- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:g.view.superview];
    g.view.center = CGPointMake(g.view.center.x + t.x, g.view.center.y + t.y);
    [g setTranslation:CGPointZero inView:g.view.superview];
    if (g.state == UIGestureRecognizerStateEnded) {
        [FDefaults() setObject:@[@(g.view.center.x), @(g.view.center.y)] forKey:kQuickPos];
        [self closePanel];
    }
}

#pragma mark - панель

- (void)toggle {
    if (self.panel) { [self closePanel]; return; }
    [self openPanel];
}

- (void)closePanel {
    [self clearTargets];
    UIView *p = self.panel;
    self.panel = nil;
    [UIView animateWithDuration:0.18 animations:^{ p.alpha = 0; p.transform = CGAffineTransformMakeScale(0.85, 0.85); }
                     completion:^(BOOL f) { [p removeFromSuperview]; }];
}

- (UIButton *)cell:(id)thing size:(CGFloat)s {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.bounds = CGRectMake(0, 0, s, s);
    b.layer.cornerRadius = 14;
    b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
    b.layer.borderWidth = 1;
    if ([thing isKindOfClass:NSDictionary.class]) {
        [b setTitle:thing[@"icon"] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:s * 0.55];
    } else if ([thing isKindOfClass:NSString.class] && [thing hasPrefix:@"/"]) {
        UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage imageWithContentsOfFile:thing]];
        iv.frame = CGRectInset(b.bounds, 6, 6);
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.userInteractionEnabled = NO;
        [b addSubview:iv];
    } else {
        [b setTitle:thing forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:s * 0.55];
    }
    return b;
}

- (void)openPanel {
    UIView *root = [self root];
    CGFloat W = 300, H = 236;
    UIView *p = FlideGlass(22);
    CGPoint c = self.fab.center;
    CGFloat x = c.x < root.bounds.size.width / 2 ? c.x + 34 : c.x - 34 - W;
    CGFloat y = MIN(MAX(c.y - H / 2, root.safeAreaInsets.top + 8), root.bounds.size.height - H - 8);
    p.frame = CGRectMake(x, y, W, H);
    UIView *content = [p isKindOfClass:UIVisualEffectView.class] ? ((UIVisualEffectView *)p).contentView : p;

    UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[L(@"😀 Эмоции"), L(@"🎁 Подарки")]];
    seg.frame = CGRectMake(12, 10, W - 24, 30);
    seg.selectedSegmentIndex = self.tab;
    seg.selectedSegmentTintColor = FlideAccent();
    [seg setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor} forState:UIControlStateNormal];
    [seg addTarget:self action:@selector(tabChanged:) forControlEvents:UIControlEventValueChanged];
    [content addSubview:seg];

    UIScrollView *grid = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 46, W, H - 70)];
    grid.tag = 50;
    [content addSubview:grid];
    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(12, H - 24, W - 24, 18)];
    hint.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightMedium];
    hint.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.tag = 51;
    [content addSubview:hint];
    [root addSubview:p];
    self.panel = p;
    [self fillGrid];

    p.alpha = 0;
    p.transform = CGAffineTransformMakeScale(0.7, 0.7);
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.62 initialSpringVelocity:0.9 options:0 animations:^{
        p.alpha = 1; p.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)tabChanged:(UISegmentedControl *)s { self.tab = s.selectedSegmentIndex; [self clearTargets]; [self fillGrid]; }

- (void)fillGrid {
    UIView *content = [self.panel isKindOfClass:UIVisualEffectView.class] ? ((UIVisualEffectView *)self.panel).contentView : self.panel;
    UIScrollView *grid = (UIScrollView *)[content viewWithTag:50];
    UILabel *hint = (UILabel *)[content viewWithTag:51];
    for (UIView *v in grid.subviews) [v removeFromSuperview];
    FlideEmotes *E = [FlideEmotes shared];
    NSArray *things;
    if (self.tab == 0) {
        things = [E slots];
        hint.text = L(@"🔒 Видишь только ты · удержи — поменять эмоцию");
    } else {
        NSMutableArray *g = [NSMutableArray arrayWithArray:[E builtinGifts]];
        [g addObjectsFromArray:[E customGifts]];
        things = g;
        hint.text = L(@"🔒 Только визуал · выбери подарок, потом игрока");
    }
    CGFloat s = 60, gap = 10, x0 = 15;
    NSInteger cols = 4;
    for (NSUInteger i = 0; i < things.count; i++) {
        UIButton *b = [self cell:things[i] size:s];
        b.center = CGPointMake(x0 + s / 2 + (i % cols) * (s + gap), 6 + s / 2 + (i / cols) * (s + gap));
        b.tag = 100 + i;
        [b addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        if (self.tab == 0) [b addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(editSlot:)]];
        [grid addSubview:b];
        // появление «волной»
        b.transform = CGAffineTransformMakeScale(0.3, 0.3); b.alpha = 0;
        [UIView animateWithDuration:0.35 delay:i * 0.025 usingSpringWithDamping:0.55 initialSpringVelocity:1 options:0 animations:^{
            b.transform = CGAffineTransformIdentity; b.alpha = 1;
        } completion:nil];
    }
    grid.contentSize = CGSizeMake(grid.bounds.size.width, 12 + ((things.count + cols - 1) / cols) * (s + gap));
}

- (void)tapped:(UIButton *)b {
    NSInteger i = b.tag - 100;
    [UIView animateWithDuration:0.1 animations:^{ b.transform = CGAffineTransformMakeScale(0.82, 0.82); }
                     completion:^(BOOL f) { [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.4 initialSpringVelocity:1 options:0 animations:^{ b.transform = CGAffineTransformIdentity; } completion:nil]; }];
    FlideEmotes *E = [FlideEmotes shared];
    if (self.tab == 0) {
        NSArray *slots = [E slots];
        if (i < (NSInteger)slots.count) [E sendEmote:slots[i]];
        [self closePanel];
        return;
    }
    NSMutableArray *g = [NSMutableArray arrayWithArray:[E builtinGifts]];
    [g addObjectsFromArray:[E customGifts]];
    if (i < (NSInteger)g.count) [self showTargetsFor:g[i]];
}

#pragma mark - цели для подарка

- (void)clearTargets { for (UIView *v in self.targets) [v removeFromSuperview]; [self.targets removeAllObjects]; }

- (void)showTargetsFor:(id)gift {
    [self clearTargets];
    UIView *root = [self root];
    NSArray<NSValue *> *pts = [[FlideEmotes shared] opponentPoints];
    NSMutableArray *all = [NSMutableArray arrayWithArray:pts];
    if (!pts.count) { // соперники не найдены — даём три точки по столу
        CGSize S = root.bounds.size;
        [all addObjectsFromArray:@[[NSValue valueWithCGPoint:CGPointMake(S.width * 0.12, S.height * 0.3)],
                                   [NSValue valueWithCGPoint:CGPointMake(S.width * 0.4, S.height * 0.18)],
                                   [NSValue valueWithCGPoint:CGPointMake(S.width * 0.88, S.height * 0.3)]]];
    }
    for (NSValue *v in all) {
        UIButton *t = [UIButton buttonWithType:UIButtonTypeCustom];
        t.bounds = CGRectMake(0, 0, 76, 76);
        t.center = v.CGPointValue;
        t.layer.cornerRadius = 38;
        t.layer.borderColor = FlideAccent().CGColor;
        t.layer.borderWidth = 3;
        t.backgroundColor = [FlideAccent() colorWithAlphaComponent:0.18];
        t.layer.shadowColor = FlideAccent().CGColor; t.layer.shadowOpacity = 1; t.layer.shadowRadius = 12; t.layer.shadowOffset = CGSizeZero;
        [t setTitle:@"🎯" forState:UIControlStateNormal];
        t.titleLabel.font = [UIFont systemFontOfSize:26];
        CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        pulse.fromValue = @0.9; pulse.toValue = @1.1; pulse.duration = 0.6; pulse.autoreverses = YES; pulse.repeatCount = HUGE_VALF;
        [t.layer addAnimation:pulse forKey:nil];
        objc_setAssociatedObject(t, "gift", gift, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(t, "pt", v, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [t addTarget:self action:@selector(throwAt:) forControlEvents:UIControlEventTouchUpInside];
        [root addSubview:t];
        [self.targets addObject:t];
    }
    // «себе» — кнопка у своего аватара
    UIButton *me = [UIButton buttonWithType:UIButtonTypeSystem];
    [me setTitle:L(@"🎁 Себе") forState:UIControlStateNormal];
    me.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    me.tintColor = UIColor.whiteColor;
    me.backgroundColor = [FlideAccent() colorWithAlphaComponent:0.7];
    me.layer.cornerRadius = 16;
    me.bounds = CGRectMake(0, 0, 92, 32);
    CGPoint mp = [[FlideEmotes shared] myPoint];
    me.center = CGPointMake(mp.x, mp.y - 60);
    objc_setAssociatedObject(me, "gift", gift, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [me addTarget:self action:@selector(throwAt:) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:me];
    [self.targets addObject:me];
}

- (void)throwAt:(UIButton *)t {
    id gift = objc_getAssociatedObject(t, "gift");
    NSValue *pt = objc_getAssociatedObject(t, "pt");
    [self closePanel];
    [[FlideEmotes shared] sendGift:gift toPoint:pt];
}

#pragma mark - замена слота

- (void)editSlot:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    self.editingSlot = g.view.tag - 100;
    UIViewController *host = [FlideMenu overlayRoot].window.rootViewController;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:L(@"Поменять эмоцию") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *em = [[FlideEmotes shared] builtinEmotes];
    [a addAction:[UIAlertAction actionWithTitle:L(@"🖼 Своя картинка из Фото") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        PHPickerConfiguration *cfg = [PHPickerConfiguration new];
        cfg.filter = [PHPickerFilter imagesFilter];
        PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:cfg];
        p.delegate = self;
        [host presentViewController:p animated:YES completion:nil];
    }]];
    for (NSString *e in em)
        [a addAction:[UIAlertAction actionWithTitle:e style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [[FlideEmotes shared] setSlot:self.editingSlot to:e]; [self fillGrid];
        }]];
    for (NSString *path in [[FlideEmotes shared] customEmotes])
        [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:L(@"Своя: %@"), path.lastPathComponent.stringByDeletingPathExtension]
                                              style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [[FlideEmotes shared] setSlot:self.editingSlot to:path]; [self fillGrid];
        }]];
    [a addAction:[UIAlertAction actionWithTitle:L(@"Отмена") style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = g.view;
    a.popoverPresentationController.sourceRect = g.view.bounds;
    [host presentViewController:a animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSItemProvider *p = results.firstObject.itemProvider;
    if (![p canLoadObjectOfClass:UIImage.class]) return;
    [p loadObjectOfClass:UIImage.class completionHandler:^(id<NSItemProviderReading> obj, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![obj isKindOfClass:UIImage.class]) return;
            NSString *path = [[FlideEmotes shared] slotFromImage:(UIImage *)obj];
            if (path) [[FlideEmotes shared] setSlot:self.editingSlot to:path];
            [self fillGrid];
        });
    }];
}

@end
