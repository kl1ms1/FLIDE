// FLIDE · мост к Unity IL2CPP через публичный il2cpp_* API.
// Ничего не захардкожено по оффсетам — классы и методы ищутся по имени в рантайме,
// поэтому переживает обновления игры.
#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

typedef void Il2CppObject;
typedef void Il2CppClass;
typedef void MethodInfo;

typedef struct { float x, y; } FVec2;
typedef struct { float x, y, z; } FVec3;
typedef struct { float x, y, width, height; } FRect;

#ifdef __cplusplus
extern "C" {
#endif

BOOL FIL_Ready(void);                                   // il2cpp загружен
Il2CppClass *FIL_Class(const char *ns, const char *name); // поиск по всем сборкам
const MethodInfo *FIL_Method(Il2CppClass *k, const char *name, int argc); // с учётом родителей
// перегрузки: sig = "UnityEngine.Texture,UnityEngine.RenderTexture"
const MethodInfo *FIL_MethodSig(Il2CppClass *k, const char *name, const char *sig);
Il2CppObject *FIL_Invoke(const MethodInfo *m, void *obj, void **args, BOOL *ok);

// хелперы
Il2CppObject *FIL_Call0(void *obj, const char *name);              // obj.name()
BOOL FIL_Call1(void *obj, const char *name, void *arg);            // obj.name(arg) -> ok
Il2CppObject *FIL_Static(const char *ns, const char *cls, const char *name, int argc, void **args);

NSString *FIL_ToNSString(Il2CppObject *str);
Il2CppObject *FIL_NewString(NSString *s);
Il2CppObject *FIL_New(Il2CppClass *k);                 // il2cpp_object_new (без конструктора)
Il2CppObject *FIL_NewByteArray(NSData *data);
Il2CppObject *FIL_TypeOf(Il2CppClass *k);
Il2CppClass *FIL_ClassOf(Il2CppObject *o);
const char *FIL_ClassName(Il2CppClass *k);
BOOL FIL_IsSubclass(Il2CppClass *k, Il2CppClass *base);

// массивы (Il2CppArray: заголовок 32 байта на arm64)
NSUInteger FIL_ArrayLength(Il2CppObject *arr);
void **FIL_ArrayData(Il2CppObject *arr);

// распаковка value-type результата
int   FIL_Int(Il2CppObject *boxed);
BOOL  FIL_Bool(Il2CppObject *boxed);
void *FIL_Unbox(Il2CppObject *boxed);

// GC-handle, чтобы держать ссылку между кадрами
uint32_t FIL_Pin(Il2CppObject *o);
Il2CppObject *FIL_Target(uint32_t h);
void FIL_Unpin(uint32_t h);

// Unity-хелперы
NSArray<NSValue *> *FIL_FindAll(const char *ns, const char *cls); // Resources.FindObjectsOfTypeAll
NSString *FIL_Name(Il2CppObject *unityObj);
int FIL_InstanceID(Il2CppObject *unityObj);
NSString *FIL_Path(Il2CppObject *component);  // Canvas/Panel/Coins/Text
BOOL FIL_ActiveInHierarchy(Il2CppObject *component);
BOOL FIL_ScreenPoint(Il2CppObject *component, CGPoint *outPointInUIKit); // центр элемента в точках UIKit

#ifdef __cplusplus
}
#endif
