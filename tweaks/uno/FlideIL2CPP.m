#import "FlideIL2CPP.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <QuartzCore/QuartzCore.h>

#define SYM(ret, name, ...) static ret (*p_##name)(__VA_ARGS__);

SYM(void *, il2cpp_domain_get, void)
SYM(void **, il2cpp_domain_get_assemblies, void *, size_t *)
SYM(void *, il2cpp_assembly_get_image, void *)
SYM(void *, il2cpp_class_from_name, void *, const char *, const char *)
SYM(const MethodInfo *, il2cpp_class_get_method_from_name, void *, const char *, int)
SYM(void *, il2cpp_runtime_invoke, const MethodInfo *, void *, void **, void **)
SYM(void *, il2cpp_string_new, const char *)
SYM(uint16_t *, il2cpp_string_chars, void *)
SYM(int32_t, il2cpp_string_length, void *)
SYM(void *, il2cpp_array_new, void *, uintptr_t)
SYM(uint32_t, il2cpp_array_length, void *)
SYM(const void *, il2cpp_class_get_type, void *)
SYM(void *, il2cpp_type_get_object, const void *)
SYM(void *, il2cpp_object_unbox, void *)
SYM(void *, il2cpp_object_get_class, void *)
SYM(const char *, il2cpp_class_get_name, void *)
SYM(void *, il2cpp_class_get_parent, void *)
SYM(uint32_t, il2cpp_gchandle_new, void *, bool)
SYM(void *, il2cpp_gchandle_get_target, uint32_t)
SYM(void, il2cpp_gchandle_free, uint32_t)
SYM(void *, il2cpp_thread_attach, void *)
SYM(void *, il2cpp_get_corlib, void)
SYM(void *, il2cpp_object_new, void *)
SYM(void, il2cpp_free, void *)
SYM(const MethodInfo *, il2cpp_class_get_methods, void *, void **)
SYM(const char *, il2cpp_method_get_name, const MethodInfo *)
SYM(uint32_t, il2cpp_method_get_param_count, const MethodInfo *)
SYM(const void *, il2cpp_method_get_param, const MethodInfo *, uint32_t)
SYM(char *, il2cpp_type_get_name, const void *)

static BOOL gReady = NO;

static BOOL loadSymbols(void) {
    if (gReady) return YES;
    void *h = RTLD_DEFAULT;
#define L(name) p_##name = (__typeof__(p_##name))dlsym(h, #name); if (!p_##name) return NO;
    L(il2cpp_domain_get) L(il2cpp_domain_get_assemblies) L(il2cpp_assembly_get_image)
    L(il2cpp_class_from_name) L(il2cpp_class_get_method_from_name) L(il2cpp_runtime_invoke)
    L(il2cpp_string_new) L(il2cpp_string_chars) L(il2cpp_string_length) L(il2cpp_array_new)
    L(il2cpp_array_length) L(il2cpp_class_get_type) L(il2cpp_type_get_object)
    L(il2cpp_object_unbox) L(il2cpp_object_get_class) L(il2cpp_class_get_name)
    L(il2cpp_class_get_parent) L(il2cpp_gchandle_new) L(il2cpp_gchandle_get_target)
    L(il2cpp_thread_attach) L(il2cpp_get_corlib) L(il2cpp_object_new)
    L(il2cpp_class_get_methods) L(il2cpp_method_get_name) L(il2cpp_method_get_param_count)
    L(il2cpp_method_get_param) L(il2cpp_type_get_name)
#undef L
    p_il2cpp_gchandle_free = (__typeof__(p_il2cpp_gchandle_free))dlsym(h, "il2cpp_gchandle_free");
    p_il2cpp_free = (__typeof__(p_il2cpp_free))dlsym(h, "il2cpp_free");
    if (!p_il2cpp_domain_get()) return NO;
    p_il2cpp_thread_attach(p_il2cpp_domain_get());
    gReady = YES;
    return YES;
}

BOOL FIL_Ready(void) { return loadSymbols(); }

// ---------- классы и методы ----------

static NSMutableDictionary<NSString *, NSValue *> *gClassCache, *gMethodCache;

Il2CppClass *FIL_Class(const char *ns, const char *name) {
    if (!loadSymbols()) return NULL;
    if (!gClassCache) gClassCache = [NSMutableDictionary new];
    NSString *key = [NSString stringWithFormat:@"%s.%s", ns, name];
    NSValue *v = gClassCache[key];
    if (v) return v.pointerValue;
    size_t n = 0;
    void **asms = p_il2cpp_domain_get_assemblies(p_il2cpp_domain_get(), &n);
    Il2CppClass *found = NULL;
    for (size_t i = 0; i < n && !found; i++) {
        void *img = p_il2cpp_assembly_get_image(asms[i]);
        if (img) found = p_il2cpp_class_from_name(img, ns, name);
    }
    if (found) gClassCache[key] = [NSValue valueWithPointer:found];
    return found;
}

const MethodInfo *FIL_Method(Il2CppClass *k, const char *name, int argc) {
    if (!k || !loadSymbols()) return NULL;
    if (!gMethodCache) gMethodCache = [NSMutableDictionary new];
    NSString *key = [NSString stringWithFormat:@"%p.%s.%d", k, name, argc];
    NSValue *v = gMethodCache[key];
    if (v) return v.pointerValue;
    const MethodInfo *m = NULL;
    for (Il2CppClass *c = k; c && !m; c = p_il2cpp_class_get_parent(c))
        m = p_il2cpp_class_get_method_from_name(c, name, argc);
    if (m) gMethodCache[key] = [NSValue valueWithPointer:m];
    return m;
}

const MethodInfo *FIL_MethodSig(Il2CppClass *k, const char *name, const char *sig) {
    if (!k || !loadSymbols()) return NULL;
    if (!gMethodCache) gMethodCache = [NSMutableDictionary new];
    NSString *key = [NSString stringWithFormat:@"%p.%s(%s)", k, name, sig];
    NSValue *v = gMethodCache[key];
    if (v) return v.pointerValue;
    NSArray *want = sig[0] ? [@(sig) componentsSeparatedByString:@","] : @[];
    for (Il2CppClass *c = k; c; c = p_il2cpp_class_get_parent(c)) {
        void *iter = NULL;
        const MethodInfo *m;
        while ((m = p_il2cpp_class_get_methods(c, &iter))) {
            if (strcmp(p_il2cpp_method_get_name(m), name) != 0) continue;
            if (p_il2cpp_method_get_param_count(m) != want.count) continue;
            BOOL match = YES;
            for (uint32_t i = 0; i < want.count && match; i++) {
                char *tn = p_il2cpp_type_get_name(p_il2cpp_method_get_param(m, i));
                match = tn && strcmp(tn, [want[i] UTF8String]) == 0;
                // строка выделена аллокатором Unity — обычный free() роняет игру
                if (tn && p_il2cpp_free) p_il2cpp_free(tn);
            }
            if (match) { gMethodCache[key] = [NSValue valueWithPointer:m]; return m; }
        }
    }
    return NULL;
}

Il2CppObject *FIL_Invoke(const MethodInfo *m, void *obj, void **args, BOOL *ok) {
    if (ok) *ok = NO;
    if (!m || !loadSymbols()) return NULL;
    void *exc = NULL;
    void *r = p_il2cpp_runtime_invoke(m, obj, args, &exc);
    if (exc) return NULL;
    if (ok) *ok = YES;
    return r;
}

Il2CppClass *FIL_ClassOf(Il2CppObject *o) { return (o && loadSymbols()) ? p_il2cpp_object_get_class(o) : NULL; }
const char *FIL_ClassName(Il2CppClass *k) { return k ? p_il2cpp_class_get_name(k) : ""; }

BOOL FIL_IsSubclass(Il2CppClass *k, Il2CppClass *base) {
    for (Il2CppClass *c = k; c; c = p_il2cpp_class_get_parent(c)) if (c == base) return YES;
    return NO;
}

Il2CppObject *FIL_Call0(void *obj, const char *name) {
    if (!obj) return NULL;
    return FIL_Invoke(FIL_Method(FIL_ClassOf(obj), name, 0), obj, NULL, NULL);
}

BOOL FIL_Call1(void *obj, const char *name, void *arg) {
    if (!obj) return NO;
    void *args[1] = { arg };
    BOOL ok = NO;
    FIL_Invoke(FIL_Method(FIL_ClassOf(obj), name, 1), obj, args, &ok);
    return ok;
}

Il2CppObject *FIL_Static(const char *ns, const char *cls, const char *name, int argc, void **args) {
    return FIL_Invoke(FIL_Method(FIL_Class(ns, cls), name, argc), NULL, args, NULL);
}

// ---------- строки, массивы, боксинг ----------

NSString *FIL_ToNSString(Il2CppObject *s) {
    if (!s || !loadSymbols()) return nil;
    return [NSString stringWithCharacters:p_il2cpp_string_chars(s) length:(NSUInteger)p_il2cpp_string_length(s)];
}

Il2CppObject *FIL_NewString(NSString *s) {
    return loadSymbols() ? p_il2cpp_string_new(s.UTF8String ?: "") : NULL;
}

Il2CppObject *FIL_New(Il2CppClass *k) { return (k && loadSymbols()) ? p_il2cpp_object_new(k) : NULL; }

Il2CppObject *FIL_NewByteArray(NSData *data) {
    Il2CppClass *byteK = FIL_Class("System", "Byte");
    if (!byteK) return NULL;
    void *arr = p_il2cpp_array_new(byteK, data.length);
    if (arr) memcpy(FIL_ArrayData(arr), data.bytes, data.length);
    return arr;
}

Il2CppObject *FIL_TypeOf(Il2CppClass *k) {
    return (k && loadSymbols()) ? p_il2cpp_type_get_object(p_il2cpp_class_get_type(k)) : NULL;
}

NSUInteger FIL_ArrayLength(Il2CppObject *arr) { return (arr && loadSymbols()) ? p_il2cpp_array_length(arr) : 0; }
void **FIL_ArrayData(Il2CppObject *arr) { return (void **)((char *)arr + 32); }

void *FIL_Unbox(Il2CppObject *b) { return (b && loadSymbols()) ? p_il2cpp_object_unbox(b) : NULL; }
int  FIL_Int(Il2CppObject *b)  { void *p = FIL_Unbox(b); return p ? *(int32_t *)p : 0; }
BOOL FIL_Bool(Il2CppObject *b) { void *p = FIL_Unbox(b); return p ? (*(uint8_t *)p != 0) : NO; }

uint32_t FIL_Pin(Il2CppObject *o) { return (o && loadSymbols()) ? p_il2cpp_gchandle_new(o, false) : 0; }
Il2CppObject *FIL_Target(uint32_t h) { return (h && loadSymbols()) ? p_il2cpp_gchandle_get_target(h) : NULL; }
void FIL_Unpin(uint32_t h) { if (h && p_il2cpp_gchandle_free) p_il2cpp_gchandle_free(h); }

// ---------- Unity ----------

NSArray<NSValue *> *FIL_FindAll(const char *ns, const char *cls) {
    Il2CppClass *k = FIL_Class(ns, cls);
    if (!k) return @[];
    void *args[1] = { FIL_TypeOf(k) };
    Il2CppObject *arr = FIL_Static("UnityEngine", "Resources", "FindObjectsOfTypeAll", 1, args);
    NSUInteger n = FIL_ArrayLength(arr);
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:n];
    void **d = arr ? FIL_ArrayData(arr) : NULL;
    for (NSUInteger i = 0; i < n; i++) if (d[i]) [out addObject:[NSValue valueWithPointer:d[i]]];
    return out;
}

NSString *FIL_Name(Il2CppObject *o) { return FIL_ToNSString(FIL_Call0(o, "get_name")) ?: @""; }
int FIL_InstanceID(Il2CppObject *o) { return FIL_Int(FIL_Call0(o, "GetInstanceID")); }

// ---------- кэши (главная оптимизация: не дёргать Unity лишний раз) ----------
// Путь объекта почти не меняется, а считать его дорого (десятки вызовов в Unity).
// Кэш по указателю живёт 30 сек — так безопасно даже при переиспользовании памяти.
static NSMutableDictionary<NSValue *, NSString *> *gPathCache;
static CFTimeInterval gPathCacheBorn;

static NSString *computePath(Il2CppObject *component) {
    NSMutableArray *parts = [NSMutableArray array];
    Il2CppObject *t = FIL_Call0(component, "get_transform");
    for (int depth = 0; t && depth < 14; depth++) {
        [parts insertObject:FIL_Name(t) atIndex:0];
        t = FIL_Call0(t, "get_parent");
    }
    return [parts componentsJoinedByString:@"/"];
}

NSString *FIL_Path(Il2CppObject *component) {
    CFTimeInterval now = CACurrentMediaTime();
    if (!gPathCache || now - gPathCacheBorn > 30 || gPathCache.count > 6000) {
        gPathCache = [NSMutableDictionary new];
        gPathCacheBorn = now;
    }
    NSValue *key = [NSValue valueWithPointer:component];
    NSString *p = gPathCache[key];
    if (!p) { p = computePath(component); gPathCache[key] = p; }
    return p;
}

BOOL FIL_ActiveInHierarchy(Il2CppObject *component) {
    Il2CppObject *go = FIL_Call0(component, "get_gameObject");
    return go ? FIL_Bool(FIL_Call0(go, "get_activeInHierarchy")) : NO;
}

BOOL FIL_ScreenPoint(Il2CppObject *component, CGPoint *out) {
    Il2CppObject *t = FIL_Call0(component, "get_transform");
    FVec3 *pos = FIL_Unbox(FIL_Call0(t, "get_position"));
    if (!pos) return NO;
    FVec3 world = *pos;
    float sx = world.x, sy = world.y;

    Il2CppObject *canvas = FIL_Call0(component, "get_canvas");
    Il2CppObject *root = canvas ? (FIL_Call0(canvas, "get_rootCanvas") ?: canvas) : NULL;
    int mode = root ? FIL_Int(FIL_Call0(root, "get_renderMode")) : 1;
    if (mode != 0) { // не Overlay — нужна камера
        Il2CppObject *cam = root ? FIL_Call0(root, "get_worldCamera") : NULL;
        if (!cam) cam = FIL_Static("UnityEngine", "Camera", "get_main", 0, NULL);
        if (!cam) return NO;
        void *args[2] = { cam, &world };
        FVec2 *sp = FIL_Unbox(FIL_Static("UnityEngine", "RectTransformUtility", "WorldToScreenPoint", 2, args));
        if (!sp) return NO;
        sx = sp->x; sy = sp->y;
    }
    // размер экрана меняется редко — спрашиваем Unity раз в секунду
    static int sw = 0, sh = 0;
    static CFTimeInterval screenAt = 0;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - screenAt > 1.0) {
        sw = FIL_Int(FIL_Static("UnityEngine", "Screen", "get_width", 0, NULL));
        sh = FIL_Int(FIL_Static("UnityEngine", "Screen", "get_height", 0, NULL));
        screenAt = now;
    }
    if (sw <= 0 || sh <= 0) return NO;
    CGSize ui = UIScreen.mainScreen.bounds.size;
    if ((sw > sh) != (ui.width > ui.height)) ui = CGSizeMake(ui.height, ui.width);
    out->x = sx * ui.width / sw;
    out->y = (sh - sy) * ui.height / sh;
    return YES;
}
