// FLIDE · общие объявления
#pragma once
#import <UIKit/UIKit.h>
#import "FlideIL2CPP.h"

#define FLog(fmt, ...) NSLog(@"[FLIDE] " fmt, ##__VA_ARGS__)

// ---------- настройки ----------
#define kNoAds        @"flide.noads"
#define kHD           @"flide.hd"
#define kFPS120       @"flide.fps120"
#define kFxTouch      @"flide.fx.touch"
#define kFxCombo      @"flide.fx.combo"
#define kFxStyle      @"flide.fx.style"
#define kFxColor      @"flide.fx.color"
#define kTexts        @"flide.texts"      // path -> string
#define kAuras        @"flide.auras"      // path -> {style, color}
#define kTextures     @"flide.textures"   // texture name -> file name
#define kBoot         @"flide.boot"
#define kBootSeconds  @"flide.boot.seconds"
#define kBootAnim     @"flide.boot.anim"  // 0 пружинка, 1 вспышка, 2 глитч, 3 печать
#define kSpoof        @"flide.clone.spoof"
#define kFunSpeed     @"flide.fun.speed"
#define kFunRainbow   @"flide.fun.rainbow"
#define kFunConfetti  @"flide.fun.confetti"
#define kFunTrail     @"flide.fun.trail"
#define kFunHaptic    @"flide.fun.haptic"
#define kFunShake     @"flide.fun.shake"
#define kFunFPS       @"flide.fun.fps"
#define kFunNight     @"flide.fun.night"     // 0…0.45 — тёплый фильтр
#define kVictoryStyle @"flide.victory.style" // 0 конфетти, 1 фейерверк, 2 всё сразу
#define kVictoryText  @"flide.victory.text"
#define kStreamer     @"flide.streamer"
#define kStreamerPaths @"flide.streamer.paths"
#define kMyAvatar     @"flide.myavatar"      // путь элемента «мой аватар»
#define kPackActive   @"flide.pack.active"
#define kTableAnim    @"flide.tableanim"     // {texture, fps}
#define kStats        @"flide.stats"
#define kFxRandom     @"flide.fx.random"     // случайный стиль на каждый бросок
#define kFunParty     @"flide.fun.party"
#define kFunClock     @"flide.fun.clock"
#define kFunShakeConfetti @"flide.fun.shakeconfetti"
#define kLang         @"flide.lang"          // ru / en
#define kUIAccent     @"flide.ui.accent"
#define kUIGlass      @"flide.ui.glass"      // 0 жидкое стекло, 1 матовое, 2 тёмное
#define kUIScale      @"flide.ui.scale"      // 0 компактно, 1 обычно, 2 крупно
#define kUILabels     @"flide.ui.labels"     // подписи в панели запуска
#define kUIAnim       @"flide.ui.anim"
#define kUIOrder      @"flide.ui.order"      // порядок иконок панели
#define kUIHidden     @"flide.ui.hidden"     // скрытые иконки
#define kQuickBar     @"flide.quick"         // быстрая кнопка эмоций на столе
#define kVictoryPath  @"flide.victory.path"  // элемент экрана победы, выбранный вручную

static inline NSUserDefaults *FDefaults(void) { return NSUserDefaults.standardUserDefaults; }
static inline BOOL FBool(NSString *k) { return [FDefaults() boolForKey:k]; }

NSString *FlideDir(NSString *sub);          // Documents/FLIDE/<sub>, создаётся
NSString *FlideSafeName(NSString *s);       // имя файла из имени текстуры
BOOL FlideGuardTripped(NSString *op);       // функция отключена после вылета
void FlideGuardCheckOnLaunch(void);
void FlideGuardReset(void);
UIColor  *FlideColorFromHex(NSString *hex);
NSString *FlideHexFromColor(UIColor *c);
UIView   *FlideGlass(CGFloat radius);       // стеклянная подложка (Liquid Glass на iOS 26)
UIColor  *FlideAccent(void);                // цвет интерфейса меню
NSString *FlideL(NSString *ru);             // перевод строки на выбранный язык
#define L(s) FlideL(s)

// ---------- фильтры картинок (редактор и темы) ----------
NSArray<NSString *> *FlideFilterNames(void);
UIImage *FlideFilterImage(UIImage *img, NSInteger filter, float hue, float strength);

// ---------- стили эффектов ----------
typedef NS_ENUM(NSInteger, FlideFxStyle) {
    FlideFxAura = 0,     // мягкие искры вверх, как зачарование
    FlideFxShadow,       // тёмный дым и летающие тени по кругу
    FlideFxFire,
    FlideFxStars,
    FlideFxRunes,        // символы-руны по спирали
    FlideFxGalaxy,       // вращающаяся туманность
    FlideFxLightning,    // молнии
    FlideFxSakura,       // лепестки сакуры
    FlideFxSnow,
    FlideFxBubbles,
    FlideFxHalo,         // нимб
    FlideFxHearts,
    FlideFxNeon,         // неоновое кольцо-радуга
    FlideFxVoid,         // чёрная дыра
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
- (UIImage *)imageOfTextureObject:(void *)tex maxSide:(int)maxSide;
- (BOOL)replaceTexture:(FlideItem *)item withImage:(UIImage *)image;
- (BOOL)resetTexture:(FlideItem *)item;           // YES — оригинал вернулся сразу
- (UIImage *)originalOfTexture:(FlideItem *)item;
- (BOOL)loadPNG:(NSData *)png intoTexture:(void *)tex;
- (NSURL *)exportTexture:(FlideItem *)item;
- (NSUInteger)exportAllTextures;
- (void)reapplyReplacements;                      // заново применить индекс (после смены пака)

// тексты
- (NSArray<FlideItem *> *)scanTexts;
- (void)setOverride:(NSString *)text forPath:(NSString *)path;
- (void)resetEverything;                          // тексты и текстуры — к исходным, сразу

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

// ---------- паки, темы, анимированный стол ----------
@interface FlidePacks : NSObject
+ (instancetype)shared;
- (void)start;
- (NSArray<NSString *> *)packs;                       // папки в FLIDE/packs
- (NSUInteger)activatePack:(NSString *)name;          // сколько текстур подставлено
- (void)deactivatePack;
- (NSURL *)savePresetNamed:(NSString *)name;          // текущие замены + настройки → пак
- (NSUInteger)importFromURLs:(NSArray<NSURL *> *)urls asPack:(NSString *)name;
- (NSURL *)zipFolder:(NSString *)path;                // zip для выгрузки (HD-апскейл)
// пресеты: у пака есть имя, иконка и режим записи
- (NSString *)titleOf:(NSString *)pack;
- (NSString *)iconOf:(NSString *)pack;
- (NSUInteger)countOf:(NSString *)pack;
- (void)rename:(NSString *)pack to:(NSString *)name;
- (void)setIcon:(NSString *)icon of:(NSString *)pack;
- (NSString *)createPreset:(NSString *)name icon:(NSString *)icon;
- (NSString *)duplicate:(NSString *)pack;
- (NSArray<NSString *> *)texturesIn:(NSString *)pack;
- (void)removeTexture:(NSString *)texture fromPreset:(NSString *)pack;
- (NSString *)recordingPreset;
- (void)setRecordingPreset:(NSString *)pack;
- (void)recordReplacement:(NSString *)texture png:(NSData *)png;
// автозамена
- (NSDictionary<NSString *, FlideItem *> *)matchTargets:(NSArray<FlideItem *> *)targets
                                                  among:(NSArray<FlideItem *> *)sources keyword:(NSString *)kw;
- (NSUInteger)replaceTargets:(NSArray<FlideItem *> *)targets withSources:(NSDictionary<NSString *, FlideItem *> *)map;
- (NSUInteger)replaceTargets:(NSArray<FlideItem *> *)targets withFiles:(NSArray<NSURL *> *)urls;
// темы — фильтр сразу ко всем текстурам
@property (nonatomic, readonly) BOOL themeRunning;
- (void)applyTheme:(NSInteger)filter progress:(void (^)(NSUInteger done, NSUInteger total))progress;
- (void)cancelTheme;
// анимированная текстура (стол)
- (BOOL)setAnimationForTexture:(NSString *)textureName frames:(NSArray<UIImage *> *)frames fps:(double)fps size:(CGSize)size;
- (void)stopAnimation;
- (NSString *)animatedTexture;
@end

// ---------- приколы ----------
@interface FlideFun : NSObject
+ (instancetype)shared;
- (void)start;
- (void)applySpeed;
- (void)applyNight;
- (void)confettiNow;
- (void)fireworksNow;
- (void)victoryNow;
- (void)shakeScreen;
- (void)countThrow:(NSUInteger)combo;
- (NSDictionary *)stats;
- (void)resetStats;
@end

// ---------- эмоции и подарки (только у тебя на экране) ----------
@interface FlideEmotes : NSObject
+ (instancetype)shared;
- (NSArray<NSString *> *)builtinEmotes;               // эмодзи
- (NSArray<NSString *> *)customEmotes;                // пути PNG
- (BOOL)addCustomEmote:(UIImage *)img;
- (void)removeCustomEmote:(NSString *)path;
- (void)sendEmote:(id)emote;                          // NSString эмодзи или путь PNG
- (NSArray<NSDictionary *> *)builtinGifts;            // {id, title, icon}
- (NSArray<NSString *> *)customGifts;
- (BOOL)addCustomGift:(UIImage *)img;
- (void)removeCustomGift:(NSString *)path;
- (void)sendGift:(id)gift toPoint:(NSValue *)target;  // nil — себе
- (NSArray *)slots;                                    // 8 слотов быстрой панели
- (void)setSlot:(NSUInteger)i to:(id)thing;
- (NSString *)slotFromImage:(UIImage *)img;
- (CGPoint)myPoint;
- (NSArray<NSValue *> *)opponentPoints;
@end

// ---------- быстрая панель эмоций/подарков на столе ----------
@interface FlideQuick : NSObject
+ (instancetype)shared;
- (void)refresh;
@end

// ---------- редактор интерфейса игры ----------
@interface FlideLayout : NSObject
+ (instancetype)shared;
- (void)start;
- (NSDictionary *)rules;
- (NSDictionary *)ruleFor:(NSString *)path;
- (void)setRule:(NSDictionary *)rule forPath:(NSString *)path;
- (void)resetAll;
- (NSArray<NSDictionary *> *)presets;
- (NSString *)activePreset;
- (void)applyPreset:(NSString *)pid;
- (NSDictionary *)userPresets;
- (void)saveUserPreset:(NSString *)name;
- (void)applyUserPreset:(NSString *)name;
- (void)deleteUserPreset:(NSString *)name;
@end

// ---------- инструменты ----------
@interface FlideTools : NSObject
+ (instancetype)shared;
- (void)toggleDrawingIn:(UIView *)host;
- (void)addSticker:(UIImage *)img in:(UIView *)host;
- (void)clearStickers;
- (void)clearAll;                                     // стикеры + рисунок
- (UIImage *)cleanScreenshot;                         // кадр игры без окон FLIDE
- (void)setClipBuffering:(BOOL)on completion:(void (^)(NSError *err))done;
- (BOOL)clipBuffering;
- (void)exportClip:(void (^)(NSURL *url, NSError *err))done;
@end

// ---------- эффекты ----------
@interface FlideFX : NSObject
+ (instancetype)shared;
- (void)start;
- (void)reloadRules;
- (void)burstAt:(CGPoint)p big:(BOOL)big;
- (void)cardThrownAt:(CGPoint)p;
- (void)highlightAt:(CGPoint)p;          // подсветить элемент игры
- (UIView *)overlayView;                 // слой поверх игры (касания проходят насквозь)
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
+ (NSArray<NSString *> *)animationNames;
@end

// ---------- меню ----------
@interface FlideMenu : NSObject
+ (void)install;
+ (void)show;                // панель запуска
+ (BOOL)isOverlayWindow:(UIWindow *)w;
+ (UIView *)overlayRoot;     // интерактивный слой окон FLIDE
+ (void)rebuildAll;          // пересобрать окна (язык, вид)
+ (void)resetToBase;         // вернуть всё к исходному виду игры
@end

void FlideToast(NSString *msg);  // стеклянное уведомление поверх всего
