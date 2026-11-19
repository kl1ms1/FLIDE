// FLIDE · режим клона: UNO FLIDE живёт рядом с обычным UNO.
// Bundle ID меняется при подписи (Feather / Sideloadly), а здесь мы
// показываем игре и её SDK оригинальный ID, чтобы вход, Firebase и прочее
// не ломались из-за «чужого» идентификатора.
#import "FlideCore.h"
#import <objc/runtime.h>

static NSString *const kOriginalBundleID = @"com.mattel163.uno";
static NSString *gRealBundleID;
static IMP gOrigBundleID, gOrigInfoKey, gOrigInfoDict;

static BOOL isMain(NSBundle *b) { return b == NSBundle.mainBundle; }

static NSString *spoofBundleIdentifier(NSBundle *self, SEL _cmd) {
    if (isMain(self)) return kOriginalBundleID;
    return ((NSString *(*)(id, SEL))gOrigBundleID)(self, _cmd);
}

static id spoofObjectForInfoKey(NSBundle *self, SEL _cmd, NSString *key) {
    if (isMain(self) && [key isEqualToString:@"CFBundleIdentifier"]) return kOriginalBundleID;
    return ((id (*)(id, SEL, NSString *))gOrigInfoKey)(self, _cmd, key);
}

static NSDictionary *spoofInfoDictionary(NSBundle *self, SEL _cmd) {
    NSDictionary *d = ((NSDictionary *(*)(id, SEL))gOrigInfoDict)(self, _cmd);
    if (!isMain(self) || !d) return d;
    NSMutableDictionary *m = [d mutableCopy];
    m[@"CFBundleIdentifier"] = kOriginalBundleID;
    return m;
}

NSString *FlideRealBundleID(void) { return gRealBundleID ?: NSBundle.mainBundle.bundleIdentifier; }
BOOL FlideIsClone(void) { return ![FlideRealBundleID() isEqualToString:kOriginalBundleID]; }

void FlideCloneInstall(void) {
    gRealBundleID = [NSBundle.mainBundle.bundleIdentifier copy];
    if (!FlideIsClone() || !FBool(kSpoof)) return;

    Class c = NSBundle.class;
    gOrigBundleID = method_setImplementation(class_getInstanceMethod(c, @selector(bundleIdentifier)), (IMP)spoofBundleIdentifier);
    gOrigInfoKey  = method_setImplementation(class_getInstanceMethod(c, @selector(objectForInfoDictionaryKey:)), (IMP)spoofObjectForInfoKey);
    gOrigInfoDict = method_setImplementation(class_getInstanceMethod(c, @selector(infoDictionary)), (IMP)spoofInfoDictionary);
    FLog(@"clone mode: %@ → %@", gRealBundleID, kOriginalBundleID);
}
