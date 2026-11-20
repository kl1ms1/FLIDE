// FLIDE · UNO! — убираем межстраничную рекламу и баннеры.
//
// Что делаем:
//   • Interstitial (полноэкранная реклама между матчами) — не грузится и «не готова».
//   • Banner — не грузится и скрыт.
// Чего НЕ делаем:
//   • Rewarded (реклама за награду) не трогаем: хочешь бонус — смотришь рекламу сам.
//   • Покупки, валюту и серверную логику не трогаем.
//
// Без зависимостей (Substrate/ElleKit не нужен) — только Objective-C runtime.
// Каждый хук ставится, только если класс и метод реально есть в приложении.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "FlideCore.h"

// ---------- helpers ----------

static BOOL hookOn(Class cls, NSString *clsName, NSString *selName, IMP newImp, IMP *orig) {
    if (!cls) return NO;
    SEL sel = NSSelectorFromString(selName);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NO;
    IMP old = method_getImplementation(m);
    // если метод унаследован — добавляем свой в этот класс, родителя не трогаем
    if (!class_addMethod(cls, sel, newImp, method_getTypeEncoding(m))) {
        method_setImplementation(m, newImp);
    }
    if (orig) *orig = old;
    FLog(@"hooked %@ %@", clsName, selName);
    return YES;
}

static BOOL hookInstance(NSString *clsName, NSString *selName, IMP newImp, IMP *orig) {
    return hookOn(NSClassFromString(clsName), clsName, selName, newImp, orig);
}

static BOOL hookClass(NSString *clsName, NSString *selName, IMP newImp) {
    Class cls = NSClassFromString(clsName);
    return cls ? hookOn(object_getClass(cls), clsName, selName, newImp, NULL) : NO;
}

// на arm64 лишние аргументы просто игнорируются — одна заглушка на любые сигнатуры
static void noop(id self, SEL _cmd) {}
static BOOL returnNO(id self, SEL _cmd) { return NO; }

static NSError *flideError(void) {
    return [NSError errorWithDomain:@"FLIDE" code:-1
                           userInfo:@{NSLocalizedDescriptionKey: @"Ad blocked by FLIDE"}];
}

// ---------- banners: держим скрытыми ----------

static NSMutableDictionary<NSString *, NSValue *> *gOrigDidMove;
static NSMutableDictionary<NSString *, NSValue *> *gOrigSetHidden;

static IMP origFor(NSDictionary *map, id obj) {
    for (Class c = object_getClass(obj); c; c = class_getSuperclass(c)) {
        NSValue *v = map[NSStringFromClass(c)];
        if (v) return (IMP)v.pointerValue;
    }
    return NULL;
}

static void bannerDidMoveToWindow(UIView *self, SEL _cmd) {
    IMP o = origFor(gOrigDidMove, self);
    if (o) ((void (*)(id, SEL))o)(self, _cmd);
    IMP h = origFor(gOrigSetHidden, self);
    if (h) ((void (*)(id, SEL, BOOL))h)(self, @selector(setHidden:), YES);
    self.alpha = 0;
    self.userInteractionEnabled = NO;
}

static void bannerSetHidden(UIView *self, SEL _cmd, BOOL hidden) {
    IMP o = origFor(gOrigSetHidden, self);
    if (o) ((void (*)(id, SEL, BOOL))o)(self, _cmd, YES);
}

static void hideBannerClass(NSString *clsName) {
    IMP o = NULL;
    if (hookInstance(clsName, @"didMoveToWindow", (IMP)bannerDidMoveToWindow, &o))
        gOrigDidMove[clsName] = [NSValue valueWithPointer:(void *)o];
    o = NULL;
    if (hookInstance(clsName, @"setHidden:", (IMP)bannerSetHidden, &o))
        gOrigSetHidden[clsName] = [NSValue valueWithPointer:(void *)o];
}

// ---------- AdMob: загрузка сразу «падает» ----------

typedef void (^GADLoadHandler)(id ad, NSError *error);

static void gadLoadFail(id self, SEL _cmd, NSString *unitID, id request, GADLoadHandler handler) {
    if (handler) dispatch_async(dispatch_get_main_queue(), ^{ handler(nil, flideError()); });
}

// ---------- страховка: любой не-наградной полноэкранный показ закрывается сразу ----------
// Наградную рекламу ты запускаешь сам — её показы помечаем на 6 секунд и пропускаем.
// Всё остальное (межстраничная из любой сети, кросс-промо, «попутная» при выходе
// из режима) открывается невидимым и тут же закрывается: SDK шлёт игре обычное
// «реклама закрыта», поэтому игра не зависает в ожидании.

static CFTimeInterval gRewardedAt = -100;
static NSMutableDictionary<NSString *, NSValue *> *gWrapped; // "Class|sel" -> оригинальный IMP

static IMP wrappedOrig(id self, SEL _cmd) {
    for (Class c = object_getClass(self); c; c = class_getSuperclass(c)) {
        NSValue *v = gWrapped[[NSString stringWithFormat:@"%s|%s", class_getName(c), sel_getName(_cmd)]];
        if (v) return (IMP)v.pointerValue;
    }
    return NULL;
}

// пробрасывает до 6 аргументов-указателей/целых (arm64: x2…x7) — этого хватает всем show-методам
static void *rewardedMark(id self, SEL _cmd, void *a, void *b, void *c, void *d, void *e, void *f) {
    gRewardedAt = CACurrentMediaTime();
    IMP o = wrappedOrig(self, _cmd);
    return o ? ((void *(*)(id, SEL, void *, void *, void *, void *, void *, void *))o)(self, _cmd, a, b, c, d, e, f) : NULL;
}

static void markRewarded(NSString *cls, NSString *sel, BOOL classMethod) {
    Class k = NSClassFromString(cls);
    if (!k) return;
    Class target = classMethod ? object_getClass(k) : k;
    SEL s = NSSelectorFromString(sel);
    Method m = class_getInstanceMethod(target, s);
    if (!m) return;
    IMP old = method_getImplementation(m);
    if (!class_addMethod(target, s, (IMP)rewardedMark, method_getTypeEncoding(m))) method_setImplementation(m, (IMP)rewardedMark);
    gWrapped[[NSString stringWithFormat:@"%s|%@", class_getName(target), sel]] = [NSValue valueWithPointer:(void *)old];
    FLog(@"rewarded pass %@ %@", cls, sel);
}

static BOOL isAdController(UIViewController *vc) {
    static NSArray *prefixes;
    if (!prefixes) prefixes = @[@"MA", @"AL", @"GAD", @"FB", @"IS", @"LPM", @"UADS", @"UnityAds", @"MTG", @"Mintegral", @"Vungle",
                                @"VNG", @"CHB", @"Moloco", @"MLC", @"IM", @"BM", @"FAD", @"STK", @"PAG", @"BU", @"Omni", @"Fyber", @"IA"];
    NSString *n = NSStringFromClass(vc.class);
    if ([n hasPrefix:@"Flide"]) return NO;
    for (NSString *p in prefixes) {
        if (![n hasPrefix:p] || n.length <= p.length) continue;
        unichar next = [n characterAtIndex:p.length];
        if ([NSCharacterSet.uppercaseLetterCharacterSet characterIsMember:next] || next == '_') return YES;
    }
    return NO;
}

static IMP gOrigPresent;
static void flidePresent(UIViewController *self, SEL _cmd, UIViewController *vc, BOOL animated, void (^completion)(void)) {
    BOOL rewarded = CACurrentMediaTime() - gRewardedAt < 6;
    if (FBool(kNoAds) && !rewarded && isAdController(vc)) {
        FLog(@"blocked fullscreen ad: %@", NSStringFromClass(vc.class));
        vc.view.alpha = 0;
        ((void (*)(id, SEL, id, BOOL, id))gOrigPresent)(self, _cmd, vc, NO, ^{
            if (completion) completion();
            dispatch_async(dispatch_get_main_queue(), ^{ [vc dismissViewControllerAnimated:NO completion:nil]; });
        });
        return;
    }
    ((void (*)(id, SEL, id, BOOL, id))gOrigPresent)(self, _cmd, vc, animated, completion);
}

static void installFullscreenGuard(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    gWrapped = [NSMutableDictionary new];
    for (NSString *s in @[@"showAd", @"showAdForPlacement:", @"showAdForPlacement:customData:", @"showAdForPlacement:customData:viewController:"]) {
        markRewarded(@"MARewardedAd", s, NO);
        markRewarded(@"MARewardedInterstitialAd", s, NO);
    }
    markRewarded(@"LPMRewardedAd", @"showAdWithViewController:placementName:", NO);
    markRewarded(@"IronSource", @"showRewardedVideoWithViewController:", YES);
    markRewarded(@"IronSource", @"showRewardedVideoWithViewController:placement:", YES);
    markRewarded(@"GADRewardedAd", @"presentFromRootViewController:userDidEarnRewardHandler:", NO);
    markRewarded(@"GADRewardedInterstitialAd", @"presentFromRootViewController:userDidEarnRewardHandler:", NO);
    markRewarded(@"FBRewardedVideoAd", @"showAdFromRootViewController:", NO);
    markRewarded(@"FBRewardedVideoAd", @"showAdFromRootViewController:animated:", NO);

    // обёртка OmniAds: наградной показ — пометить, межстраничный/веб/кросс-промо — заглушить
    unsigned int n = 0;
    Class *all = objc_copyClassList(&n);
    for (unsigned int i = 0; i < n; i++) {
        const char *name = class_getName(all[i]);
        if (strncmp(name, "Omni", 4) != 0) continue;
        NSString *cn = @(name);
        if (class_getInstanceMethod(all[i], NSSelectorFromString(@"showRewardAdSource"))) markRewarded(cn, @"showRewardAdSource", NO);
        for (NSString *s in @[@"showCrossPromotionViewWithModel:", @"showInterstitialsAdSourceWithMuteVoice:", @"showWebAdSourceWithSpaceId:"])
            if (class_getInstanceMethod(all[i], NSSelectorFromString(s))) hookInstance(cn, s, (IMP)noop, NULL);
    }
    free(all);

    Method m = class_getInstanceMethod(UIViewController.class, @selector(presentViewController:animated:completion:));
    gOrigPresent = method_setImplementation(m, (IMP)flidePresent);
}

// ---------- entry ----------

static void installHooks(void) {
    static BOOL done = NO;
    if (done || !FBool(kNoAds)) return;
    // рекламные SDK живут в UnityFramework, который Unity грузит уже после старта
    if (!NSClassFromString(@"MAInterstitialAd") && !NSClassFromString(@"GADInterstitialAd")) return;
    done = YES;

    gOrigDidMove   = [NSMutableDictionary new];
    gOrigSetHidden = [NSMutableDictionary new];

    // AppLovin MAX — interstitial
    hookInstance(@"MAInterstitialAd", @"isReady", (IMP)returnNO, NULL);
    hookInstance(@"MAInterstitialAd", @"loadAd", (IMP)noop, NULL);
    for (NSString *s in @[@"showAd", @"showAdForPlacement:", @"showAdForPlacement:customData:",
                          @"showAdForPlacement:customData:viewController:"])
        hookInstance(@"MAInterstitialAd", s, (IMP)noop, NULL);

    // AppLovin MAX — banner
    hookInstance(@"MAAdView", @"loadAd", (IMP)noop, NULL);
    hookInstance(@"MAAdView", @"startAutoRefresh", (IMP)noop, NULL);
    hideBannerClass(@"MAAdView");

    // Google AdMob — interstitial / app open / banner
    hookClass(@"GADInterstitialAd", @"loadWithAdUnitID:request:completionHandler:", (IMP)gadLoadFail);
    hookClass(@"GADAppOpenAd",      @"loadWithAdUnitID:request:completionHandler:", (IMP)gadLoadFail);
    hookInstance(@"GADInterstitialAd", @"canPresentFromRootViewController:error:", (IMP)returnNO, NULL);
    hookInstance(@"GADInterstitialAd", @"presentFromRootViewController:", (IMP)noop, NULL);
    hookInstance(@"GADAppOpenAd",      @"presentFromRootViewController:", (IMP)noop, NULL);
    hookInstance(@"GADBannerView", @"loadRequest:", (IMP)noop, NULL);
    hideBannerClass(@"GADBannerView");

    // IronSource / LevelPlay
    hookInstance(@"LPMInterstitialAd", @"isAdReady", (IMP)returnNO, NULL);
    hookInstance(@"LPMInterstitialAd", @"loadAd", (IMP)noop, NULL);
    hookInstance(@"LPMInterstitialAd", @"showAdWithViewController:placementName:", (IMP)noop, NULL);
    hookClass(@"IronSource", @"hasInterstitial", (IMP)returnNO);
    hookClass(@"IronSource", @"loadInterstitial", (IMP)noop);
    hookClass(@"IronSource", @"showInterstitialWithViewController:", (IMP)noop);
    hookClass(@"IronSource", @"showInterstitialWithViewController:placement:", (IMP)noop);
    hookInstance(@"LPMBannerAdView", @"loadAdWithViewController:", (IMP)noop, NULL);
    hideBannerClass(@"LPMBannerAdView");
    hideBannerClass(@"ISBannerView");

    // Meta Audience Network
    hookInstance(@"FBInterstitialAd", @"isAdValid", (IMP)returnNO, NULL);
    hookInstance(@"FBInterstitialAd", @"showAdFromRootViewController:", (IMP)returnNO, NULL);
    hideBannerClass(@"FBAdView");

    installFullscreenGuard();
    FLog(@"UNO no-ads loaded ✦");
}

__attribute__((constructor))
static void flideInit(void) {
    [FDefaults() registerDefaults:@{ kNoAds: @YES, kBoot: @YES, kSpoof: @YES, kFxTouch: @YES, kFxCombo: @YES, kFxColor: @"#7CF7FF", kUILabels: @YES, kUIAnim: @YES, kUIScale: @1, kFunConfetti: @YES, kQuickBar: @YES }];
    FlideGuardCheckOnLaunch(); // если прошлый запуск упал — отключим виновника
    FlideCloneInstall();   // первым делом, до SDK
    installHooks();
    [[FlideEngine shared] start];
    [FlideMenu install];
    [FlideBoot install];
    [[FlidePacks shared] start];
    [[FlideFun shared] start];
    [[FlideLayout shared] start];
    [[NSNotificationCenter defaultCenter] addObserverForName:NSBundleDidLoadNotification
        object:nil queue:nil usingBlock:^(NSNotification *n) { installHooks(); }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
        object:nil queue:nil usingBlock:^(NSNotification *n) { installHooks(); }];
}
