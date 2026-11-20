// FLIDE · стикер-паки: папки в Documents/FLIDE/stickers/<пак>/ с PNG, JPG и GIF.
// GIF играет как анимация в пузыре эмоции. Только у тебя на экране.
#import "FlideCore.h"
#import <ImageIO/ImageIO.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// Картинка из файла; GIF и многокадровые — анимированным UIImage (до 40 кадров, сжатые до maxSide)
UIImage *FlideLoadImage(NSString *path, CGFloat maxSide) {
    static NSCache<NSString *, UIImage *> *cache;
    if (!cache) { cache = [NSCache new]; cache.countLimit = 60; }
    NSString *key = [NSString stringWithFormat:@"%@|%.0f", path, maxSide];
    UIImage *hit = [cache objectForKey:key];
    if (hit) return hit;
    NSData *data = [NSData dataWithContentsOfFile:path];
    CGImageSourceRef src = data ? CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL) : NULL;
    if (!src) return nil;
    size_t n = CGImageSourceGetCount(src);
    NSDictionary *opt = @{(id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                          (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
                          (id)kCGImageSourceThumbnailMaxPixelSize: @(maxSide * UIScreen.mainScreen.scale)};
    UIImage *result = nil;
    if (n <= 1) {
        CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opt);
        if (cg) { result = [UIImage imageWithCGImage:cg scale:UIScreen.mainScreen.scale orientation:UIImageOrientationUp]; CGImageRelease(cg); }
    } else {
        NSMutableArray *frames = [NSMutableArray new];
        double total = 0;
        size_t step = MAX((size_t)1, n / 40);
        for (size_t i = 0; i < n; i += step) {
            CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(src, i, (__bridge CFDictionaryRef)opt);
            if (cg) { [frames addObject:[UIImage imageWithCGImage:cg scale:UIScreen.mainScreen.scale orientation:UIImageOrientationUp]]; CGImageRelease(cg); }
            NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src, i, NULL));
            NSNumber *d = props[(NSString *)kCGImagePropertyGIFDictionary][(NSString *)kCGImagePropertyGIFUnclampedDelayTime]
                       ?: props[(NSString *)kCGImagePropertyGIFDictionary][(NSString *)kCGImagePropertyGIFDelayTime];
            total += (d.doubleValue > 0.01 ? d.doubleValue : 0.1) * step;
        }
        result = frames.count > 1 ? [UIImage animatedImageWithImages:frames duration:MAX(0.2, total)] : frames.firstObject;
    }
    CFRelease(src);
    if (result) [cache setObject:result forKey:key];
    return result;
}

@implementation FlideStickers

+ (instancetype)shared {
    static FlideStickers *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [FlideStickers new]; });
    return s;
}

- (NSString *)root { return FlideDir(@"stickers"); }
- (NSString *)dirOf:(NSString *)pack { return [[self root] stringByAppendingPathComponent:pack]; }

- (NSArray<NSString *> *)packs {
    NSMutableArray *out = [NSMutableArray new];
    for (NSString *n in [NSFileManager.defaultManager contentsOfDirectoryAtPath:[self root] error:nil]) {
        BOOL dir = NO;
        [NSFileManager.defaultManager fileExistsAtPath:[self dirOf:n] isDirectory:&dir];
        if (dir && ![n hasPrefix:@"."]) [out addObject:n];
    }
    return [out sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (NSString *)createPack:(NSString *)name {
    NSString *pack = FlideSafeName(name);
    [NSFileManager.defaultManager createDirectoryAtPath:[self dirOf:pack] withIntermediateDirectories:YES attributes:nil error:nil];
    return pack;
}

- (void)deletePack:(NSString *)pack { [NSFileManager.defaultManager removeItemAtPath:[self dirOf:pack] error:nil]; }

static BOOL isImageExt(NSString *ext) {
    return [@[@"png", @"gif", @"jpg", @"jpeg", @"webp", @"heic"] containsObject:ext.lowercaseString];
}

- (NSArray<NSString *> *)filesInPack:(NSString *)pack {
    NSMutableArray *out = [NSMutableArray new];
    NSString *dir = [self dirOf:pack];
    for (NSString *f in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil] sortedArrayUsingSelector:@selector(compare:)])
        if (isImageExt(f.pathExtension)) [out addObject:[dir stringByAppendingPathComponent:f]];
    return out;
}

- (void)removeFile:(NSString *)path { [NSFileManager.defaultManager removeItemAtPath:path error:nil]; }

- (BOOL)addData:(NSData *)data ext:(NSString *)ext toPack:(NSString *)pack {
    if (!data.length || !isImageExt(ext)) return NO;
    static NSUInteger counter;
    NSString *name = [NSString stringWithFormat:@"%.0f_%lu.%@", NSDate.date.timeIntervalSince1970 * 1000, (unsigned long)counter++, ext.lowercaseString];
    [NSFileManager.defaultManager createDirectoryAtPath:[self dirOf:pack] withIntermediateDirectories:YES attributes:nil error:nil];
    return [data writeToFile:[[self dirOf:pack] stringByAppendingPathComponent:name] atomically:YES];
}

- (NSUInteger)importURLs:(NSArray<NSURL *> *)urls intoPack:(NSString *)pack {
    NSUInteger n = 0;
    for (NSURL *u in urls) {
        BOOL scoped = [u startAccessingSecurityScopedResource];
        BOOL isDir = NO;
        [NSFileManager.defaultManager fileExistsAtPath:u.path isDirectory:&isDir];
        NSMutableArray *files = [NSMutableArray new];
        if (isDir) for (NSString *rel in [NSFileManager.defaultManager enumeratorAtPath:u.path]) [files addObject:[u.path stringByAppendingPathComponent:rel]];
        else [files addObject:u.path];
        for (NSString *f in files)
            if (isImageExt(f.pathExtension) && [self addData:[NSData dataWithContentsOfFile:f] ext:f.pathExtension toPack:pack]) n++;
        if (scoped) [u stopAccessingSecurityScopedResource];
    }
    return n;
}

// Из «Фото»: GIF остаётся GIF (анимация сохраняется), остальное — PNG
- (void)importPickerResults:(NSArray<PHPickerResult *> *)results intoPack:(NSString *)pack completion:(void (^)(NSUInteger))done {
    dispatch_group_t g = dispatch_group_create();
    __block NSUInteger n = 0;
    NSObject *lock = [NSObject new];
    for (PHPickerResult *r in results) {
        NSItemProvider *p = r.itemProvider;
        dispatch_group_enter(g);
        if ([p hasItemConformingToTypeIdentifier:UTTypeGIF.identifier]) {
            [p loadDataRepresentationForTypeIdentifier:UTTypeGIF.identifier completionHandler:^(NSData *d, NSError *e) {
                BOOL ok = d && [self addData:d ext:@"gif" toPack:pack];
                if (ok) @synchronized (lock) { n++; }
                dispatch_group_leave(g);
            }];
        } else if ([p canLoadObjectOfClass:UIImage.class]) {
            [p loadObjectOfClass:UIImage.class completionHandler:^(id<NSItemProviderReading> obj, NSError *e) {
                NSData *png = [obj isKindOfClass:UIImage.class] ? UIImagePNGRepresentation((UIImage *)obj) : nil;
                if (png && [self addData:png ext:@"png" toPack:pack]) @synchronized (lock) { n++; }
                dispatch_group_leave(g);
            }];
        } else dispatch_group_leave(g);
    }
    dispatch_group_notify(g, dispatch_get_main_queue(), ^{ if (done) done(n); });
}

@end
