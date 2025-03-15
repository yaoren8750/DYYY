/*自行扩展功能 本人仅做一个简单的框架与部分功能*/

#import "XZ.h"

UIViewController *topView(void) {
    UIWindow *window;
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            window = scene.windows.firstObject;
            break;
        }
    }

    UIViewController *rootVC = window.rootViewController;

    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }

    if ([rootVC isKindOfClass:[UINavigationController class]]) {
        return ((UINavigationController *)rootVC).topViewController;
    }

    return rootVC;
}

void showTextInputAlert(NSString *title, void (^onConfirm)(id text), void (^onCancel)(void)) {
    AFDTextInputAlertController *alertController = [[%c(AFDTextInputAlertController) alloc] init];
    alertController.title = title;

    AFDAlertAction *okAction = [%c(AFDAlertAction) actionWithTitle:@"确定" style:0 handler:^{
        if (onConfirm) {
            onConfirm(alertController.textField.text);
        }
    }];

    AFDAlertAction *noAction = [%c(AFDAlertAction) actionWithTitle:@"取消" style:1 handler:^{
        if (onCancel) {
            onCancel();
        }
    }];

    alertController.actions = @[noAction, okAction];

    AFDTextField *textField = [[%c(AFDTextField) alloc] init];
    textField.textMaxLength = 50;
    alertController.textField = textField;
    if ([UIScreen mainScreen].traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        alertController.textField.textColor = [UIColor whiteColor];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [topView() presentViewController:alertController animated:YES completion:nil];
    });
}

bool getUserDefaults(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

void setUserDefaults(id object, NSString *key) {
    [[NSUserDefaults standardUserDefaults] setObject:object forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

void showToast(NSString *text) {
    [%c(DUXToast) showText:text];
}

void saveMedia(NSURL *mediaURL, MediaType mediaType, void (^completion)(void)) {
    if (mediaType == MediaTypeAudio) {
        return;
    }

    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status == PHAuthorizationStatusAuthorized) {
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                if (mediaType == MediaTypeVideo) {
                    [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:mediaURL];
                } else {
                    UIImage *image = [UIImage imageWithContentsOfFile:mediaURL.path];
                    if (image) {
                        [PHAssetChangeRequest creationRequestForAssetFromImage:image];
                    }
                }
            } completionHandler:^(BOOL success, NSError * _Nullable error) {
                if (success) {
                    if (completion) {
                        completion();
                    }
                } else {
                    showToast(@"保存失败");
                }
                [[NSFileManager defaultManager] removeItemAtPath:mediaURL.path error:nil];
            }];
        }
    }];
}

void downloadMedia(NSURL *url, MediaType mediaType, void (^completion)(void)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        AWEProgressLoadingView *loadingView = [[%c(AWEProgressLoadingView) alloc] initWithType:0 title:@"解析中..."];
        [loadingView showOnView:[UIApplication sharedApplication].keyWindow animated:YES];

        NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:nil delegateQueue:[NSOperationQueue mainQueue]];
        NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [loadingView dismissAnimated:YES];
            });

            if (!error) {
                NSString *fileName = url.lastPathComponent;

                if (!fileName.pathExtension.length) {
                    switch (mediaType) {
                        case MediaTypeVideo:
                            fileName = [fileName stringByAppendingPathExtension:@"mp4"];
                            break;
                        case MediaTypeImage:
                            fileName = [fileName stringByAppendingPathExtension:@"jpg"];
                            break;
                        case MediaTypeAudio:
                            fileName = [fileName stringByAppendingPathExtension:@"mp3"];
                            break;
                    }
                }

                NSURL *tempDir = [NSURL fileURLWithPath:NSTemporaryDirectory()];
                NSURL *destinationURL = [tempDir URLByAppendingPathComponent:fileName];
                [[NSFileManager defaultManager] moveItemAtURL:location toURL:destinationURL error:nil];

                if (mediaType == MediaTypeAudio) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[destinationURL] applicationActivities:nil];

                        [activityVC setCompletionWithItemsHandler:^(UIActivityType _Nullable activityType, BOOL completed, NSArray * _Nullable returnedItems, NSError * _Nullable error) {
                            [[NSFileManager defaultManager] removeItemAtURL:destinationURL error:nil];
                        }];
                        UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
                        [rootVC presentViewController:activityVC animated:YES completion:nil];
                    });
                } else {
                    saveMedia(destinationURL, mediaType, completion);
                }
            } else {
                showToast(@"下载失败");
            }
        }];
        [downloadTask resume];
    });
}

void downloadAllImages(NSArray<NSString *> *imageURLs) {
    dispatch_group_t group = dispatch_group_create();
    __block NSInteger downloadCount = 0;

    for (NSString *imageURL in imageURLs) {
        NSURL *url = [NSURL URLWithString:imageURL];
        dispatch_group_enter(group);

        downloadMedia(url, MediaTypeImage, ^{
            dispatch_group_leave(group);
        });
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        showToast(@"所有图片保存完成");
    });
}

%hook AWEPlayInteractionViewController

- (void)onVideoPlayerViewDoubleClicked:(UITapGestureRecognizer *)tapGes {
    if (getUserDefaults(@"DYYYDoubleClickedComment")) {
        [self performCommentAction];
        return;
    }
    if (!getUserDefaults(@"DYYYDoubleClickedDownload")) return %orig;
    AWEAwemeModel *awemeModel = self.model;
    AWEVideoModel *videoModel = awemeModel.video;
    AWEMusicModel *musicModel = awemeModel.music;

    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"无水印解析" message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    NSString *typeStr = @"下载视频";
    NSInteger aweType = awemeModel.awemeType;
    int allImages = 0;

    if (aweType == 68) {
        typeStr = @"下载图片";
        allImages = 1;
    }

    [alertController addAction:[UIAlertAction actionWithTitle:typeStr style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSURL *url = nil;
        if (aweType == 68) {
            AWEImageAlbumImageModel *currentImageModel = awemeModel.albumImages.count == 1 ? awemeModel.albumImages.firstObject : awemeModel.albumImages[awemeModel.currentImageIndex - 1];
            url = [NSURL URLWithString:currentImageModel.urlList.firstObject];
            downloadMedia(url, MediaTypeImage, ^{
                showToast(@"图片已保存到相册");
            });
        } else {
            url = [NSURL URLWithString:videoModel.h264URL.originURLList.firstObject];
            downloadMedia(url, MediaTypeVideo, ^{
                showToast(@"视频已保存到相册");
            });
        }
    }]];

    if (allImages) {
        [alertController addAction:[UIAlertAction actionWithTitle:@"下载全图" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSMutableArray *imageURLs = [NSMutableArray array];
            for (AWEImageAlbumImageModel *imageModel in awemeModel.albumImages) {
                [imageURLs addObject:imageModel.urlList.firstObject];
            }
            downloadAllImages(imageURLs);
        }]];
    }

    [alertController addAction:[UIAlertAction actionWithTitle:@"下载音频" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSURL *url = [NSURL URLWithString:musicModel.playURL.originURLList.firstObject];
        downloadMedia(url, MediaTypeAudio, nil);
    }]];

    [alertController addAction:[UIAlertAction actionWithTitle:@"下载封面" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSURL *url = [NSURL URLWithString:videoModel.coverURL.originURLList.firstObject];
        downloadMedia(url, MediaTypeImage, ^{
            showToast(@"封面已保存到相册");
        });
    }]];

    [alertController addAction:[UIAlertAction actionWithTitle:@"点赞视频" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        %orig;
    }]];

    [alertController addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    [self presentViewController:alertController animated:YES completion:nil];
}

%end

%hook AWELongPressPanelTableViewController

- (NSArray *)dataArray {
    NSArray *originalArray = %orig;
    if (!getUserDefaults(@"DYYYLongPressDownload")) return originalArray;

    AWELongPressPanelViewGroupModel *newGroupModel = [[%c(AWELongPressPanelViewGroupModel) alloc] init];
    newGroupModel.groupType = 0;

    AWELongPressPanelBaseViewModel *tempViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
    AWEAwemeModel *awemeModel = tempViewModel.awemeModel;
    AWEVideoModel *videoModel = awemeModel.video;
    AWEMusicModel *musicModel = awemeModel.music;
    AWEImageAlbumImageModel *currentImageModel = awemeModel.albumImages.count == 1 ? awemeModel.albumImages.firstObject : awemeModel.albumImages[awemeModel.currentImageIndex - 1];

    NSArray *customButtons = @[@"下载视频", @"下载音频", @"下载封面"];
    NSArray *customIcons = @[@"ic_star_outlined_12", @"ic_star_outlined_12", @"ic_star_outlined_12", @"ic_star_outlined_12"];
    if (awemeModel.awemeType == 68) {
        customButtons = @[@"下载图片", @"下载全图", @"下载音频", @"下载封面"];
    }

    NSMutableArray *viewModels = [NSMutableArray arrayWithCapacity:customButtons.count];

    for (NSUInteger i = 0; i < customButtons.count; i++) {
        AWELongPressPanelBaseViewModel *viewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        viewModel.describeString = customButtons[i];
        viewModel.enterMethod = DYYY;
        bool allImages = [customButtons[i] isEqualToString:@"下载全图"];
        viewModel.actionType = allImages ? 123 : 100 + i;
        viewModel.showIfNeed = YES;
        viewModel.duxIconName = customIcons[i];

        viewModel.action = ^{
            NSURL *url = nil;
            switch (viewModel.actionType) {
                case 100:
                    if (awemeModel.awemeType == 68) {
                        url = [NSURL URLWithString:currentImageModel.urlList.firstObject];
                        downloadMedia(url, MediaTypeImage, ^{
                            showToast(@"图片已保存到相册");
                        });
                    } else {
                        url = [NSURL URLWithString:videoModel.h264URL.originURLList.firstObject];
                        downloadMedia(url, MediaTypeVideo, ^{
                            showToast(@"视频已保存到相册");
                        });
                    }
                    break;
                case 101:
                    url = [NSURL URLWithString:musicModel.playURL.originURLList.firstObject];
                    downloadMedia(url, MediaTypeAudio, nil);
                    break;
                case 102:
                    url = [NSURL URLWithString:videoModel.coverURL.originURLList.firstObject];
                    downloadMedia(url, MediaTypeImage, ^{
                        showToast(@"封面已保存到相册");
                    });
                    break;
                case 123:
                    NSMutableArray *imageURLs = [NSMutableArray array];
                    for (AWEImageAlbumImageModel *imageModel in awemeModel.albumImages) {
                        [imageURLs addObject:imageModel.urlList.firstObject];
                    }
                    downloadAllImages(imageURLs);
                    break;
            }
        };

        [viewModels addObject:viewModel];
    }

    newGroupModel.groupArr = viewModels;
    return [@[newGroupModel] arrayByAddingObjectsFromArray:originalArray ?: @[]];
}

%end

%hook AWECommentMediaDownloadConfigLivePhoto

bool commentLivePhotoNotWaterMark = getUserDefaults(@"DYYYCommentLivePhotoNotWaterMark");

- (bool)needClientWaterMark {
    return commentLivePhotoNotWaterMark ? 0 : %orig;
}

- (bool)needClientEndWaterMark {
    return commentLivePhotoNotWaterMark ? 0 : %orig;
}

- (id)watermarkConfig {
    return commentLivePhotoNotWaterMark ? nil : %orig;
}

%end