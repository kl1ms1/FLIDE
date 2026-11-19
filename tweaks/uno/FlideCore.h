// FLIDE · общие объявления
#pragma once
#import <UIKit/UIKit.h>
#import "FlideIL2CPP.h"

#define FLog(fmt, ...) NSLog(@"[FLIDE] " fmt, ##__VA_ARGS__)

// ---------- настройки ----------
#define kNoAds      @"flide.noads"
#define kHD         @"flide.hd"
#define kFPS120     @"flide.fps120"
#define kFxTouch    @"flide.fx.touch"
#define kFxCombo    @"flide.fx.combo"
#define kFxStyle    @"flide.fx.style"
#define kFxColor    @"flide.fx.color"
#define kTexts      @"flide.texts"     // path -> string
#define kAuras      @"flide.auras"     // path -> {style, color}
#define kTextures   @"flide.textures"  // texture name -> file name
#define kBoot       @"flide.boot"
#define kBootSeconds @"flide.boot.seconds"
#define kSpoof      @"flide.clone.spoof"
#define kFunSpeed   @"flide.fun.speed"
#define kFunRainbow @"flide.fun.rainbow"
#define kFunConfetti @"flide.fun.confetti"
#define kFunTrail   @"flide.fun.trail"
#define kFunHaptic  @"flide.fun.haptic"
#define kFunShake   @"flide.fun.shake"
#define kFunFPS     @"flide.fun.fps"

static inline NSUserDefaults *FDefaults(void) { return NSUserDefaults.standardUserDefaults; }
static inline BOOL FBool(NSString *k) { return [FDefaults() boolForKey:k]; }

NSString *FlideDir(NSString *sub);
BOOL FlideGuardTripped(NSString *op);       // функция отключена после вылета
void FlideGuardCheckOnLaunch(void);
void FlideGuardReset(void);          // Documents/FLIDE/<sub>, создаётся
UIColor  *FlideColorFromHex(NSString *hex);
NSString *FlideHexFromColor(UIColor *c);

// ---------- стили эффектов ----------
typedef NS_ENUM(NSInteger, FlideFxStyle) {
    FlideFxAura = 0,     // мягкие искры вверх, как зачарование
    FlideFxShadow,       // тёмный дым и летающие тени по кругу
    FlideFxFire,
    FlideFxStars,
    FlideFxRunes,        // символы-руны по спирали
    FlideFxStyleCount
};
NSString *FlideFxStyleName(FlideFxStyle s);

// ---------- движок Unity ----------
@interface FlideItem : NSObject
@property (nonatomic, copy)   NSString *name;    // имя текстуры / путь объекта
@property (nonatomic, copy)   NSString *detail;  // размер / текущий текст / тип
@property (nonatomic, assign) int instanceID;
@property (nonatomic, assign) uint32_t handle;   // GC handle
@property (nonatomic, strong) UIImage *preview;
@end

@interface FlideEngine : NSObject
+ (instancetype)shared;
- (void)start;

// текстуры
- (NSArray<FlideItem *> *)scanTextures;
- (UIImage *)imageOfTexture:(FlideItem *)item maxSide:(int)maxSide;
- (BOOL)replaceTexture:(FlideItem *)item withImage:(UIImage *)image;
- (BOOL)resetTexture:(FlideItem *)item;           // YES — оригинал вернулся сразу
- (UIImage *)originalOfTexture:(FlideItem *)item;
- (NSURL *)exportTexture:(FlideItem *)item;
- (NSUInteger)exportAllTextures;

// тексты
- (NSArray<FlideItem *> *)scanTexts;
- (void)setOverride:(NSString *)text forPath:(NSString *)path;

// элементы интерфейса для эффектов
- (NSArray<FlideItem *> *)scanElements;
- (BOOL)screenPointForPath:(NSString *)path point:(CGPoint *)pt;

- (void)applyQuality;
- (void)releaseItems:(NSArray<FlideItem *> *)items;    // отпустить GC-хэндлы списка
- (BOOL)screenPointForItem:(FlideItem *)item point:(CGPoint *)pt;
@end

// ---------- редактор текстуры ----------
@interface FlideTextureEditor : UIViewController
+ (instancetype)editorForItem:(FlideItem *)item onChange:(void (^)(void))onChange;
@end

// ---------- приколы ----------
@interface FlideFun : NSObject
+ (instancetype)shared;
- (void)start;
- (void)applySpeed;
- (void)confettiNow;
- (void)shakeScreen;
@end

// ---------- эффекты ----------
@interface FlideFX : NSObject
+ (instancetype)shared;
- (void)start;
- (void)reloadRules;
- (void)burstAt:(CGPoint)p big:(BOOL)big;
- (void)cardThrownAt:(CGPoint)p;
- (void)highlightAt:(CGPoint)p;          // подсветить элемент игры
- (UIView *)overlayView;                 // слой поверх игры (для FPS и конфетти)
@end

// ---------- режим клона ----------
void FlideCloneInstall(void);
NSString *FlideRealBundleID(void);
BOOL FlideIsClone(void);

// ---------- бут-лого ----------
@interface FlideBoot : NSObject
+ (void)install;
+ (void)showAnimated;
+ (BOOL)setCustomImage:(UIImage *)img;   // nil — вернуть стандартное
+ (BOOL)hasCustomImage;
@end

// ---------- меню ----------
@interface FlideMenu : NSObject
+ (void)install;
+ (void)show;                // панель запуска
+ (BOOL)isOverlayWindow:(UIWindow *)w;
@end
