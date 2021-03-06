//
//  TZPhotoPickerController.m
//  TZImagePickerController
//
//  Created by 谭真 on 15/12/24.
//  Copyright © 2015年 谭真. All rights reserved.
//

#import "TZPhotoPickerController.h"
#import "TZImagePickerController.h"
#import "TZPhotoPreviewController.h"
#import "TZAssetCell.h"
#import "TZAssetModel.h"
#import "UIView+Layout.h"
#import "TZImageManager.h"
#import "TZVideoPlayerController.h"
#import "TZGifPhotoPreviewController.h"
#import "TZLocationManager.h"
#import "LZImageCropping.h"
#import "ZLEditVideoController.h"

#define RGBHex(rgbValue) \
[UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 \
green:((float)((rgbValue & 0x00FF00) >>  8))/255.0 \
blue:((float)((rgbValue & 0x0000FF) >>  0))/255.0 \
alpha:1.0]

@interface TZPhotoPickerController ()<UICollectionViewDataSource,UICollectionViewDelegate,UIImagePickerControllerDelegate,UINavigationControllerDelegate,UIAlertViewDelegate,LZImageCroppingDelegate> {
    NSMutableArray *_models;
    
    UIView *_bottomToolBar;
    UIButton *_previewButton;
    UIButton *_doneButton;
    UIImageView *_numberImageView;
    UILabel *_numberLabel;
    UIButton *_originalPhotoButton;
    UILabel *_originalPhotoLabel;
    UIView *_divideLine;
    
    BOOL _shouldScrollToBottom;
    BOOL _showTakePhotoBtn;
    
    CGFloat _offsetItemCount;
}
@property CGRect previousPreheatRect;
@property (nonatomic, assign) BOOL isSelectOriginalPhoto;
@property (nonatomic, strong) TZCollectionView *collectionView;
@property (strong, nonatomic) UICollectionViewFlowLayout *layout;
@property (nonatomic, strong) UIImagePickerController *imagePickerVc;
@property (strong, nonatomic) CLLocation *location;
@end

static CGSize AssetGridThumbnailSize;
static CGFloat itemMargin = 5;

@implementation TZPhotoPickerController

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (UIImagePickerController *)imagePickerVc {
    if (_imagePickerVc == nil) {
        _imagePickerVc = [[UIImagePickerController alloc] init];
        _imagePickerVc.delegate = self;
        // set appearance / 改变相册选择页的导航栏外观
        if (iOS7Later) {
            _imagePickerVc.navigationBar.barTintColor = self.navigationController.navigationBar.barTintColor;
        }
        _imagePickerVc.navigationBar.tintColor = self.navigationController.navigationBar.tintColor;
        UIBarButtonItem *tzBarItem, *BarItem;
        if (iOS9Later) {
            tzBarItem = [UIBarButtonItem appearanceWhenContainedInInstancesOfClasses:@[[TZImagePickerController class]]];
            BarItem = [UIBarButtonItem appearanceWhenContainedInInstancesOfClasses:@[[UIImagePickerController class]]];
        } else {
            tzBarItem = [UIBarButtonItem appearanceWhenContainedIn:[TZImagePickerController class], nil];
            BarItem = [UIBarButtonItem appearanceWhenContainedIn:[UIImagePickerController class], nil];
        }
        NSDictionary *titleTextAttributes = [tzBarItem titleTextAttributesForState:UIControlStateNormal];
        [BarItem setTitleTextAttributes:titleTextAttributes forState:UIControlStateNormal];
    }
    return _imagePickerVc;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.isFirstAppear = YES;
    TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
    _isSelectOriginalPhoto = tzImagePickerVc.isSelectOriginalPhoto;
    _shouldScrollToBottom = YES;
    self.view.backgroundColor = [UIColor whiteColor];
    // 如果仅仅选择视频 title就固定显示"选择视频"
    // 其他情况显示当前相册名称
    if (tzImagePickerVc.allowPickingImage == NO && tzImagePickerVc.allowPickingGif == NO  && tzImagePickerVc.allowPickingVideo == YES) {
        self.navigationItem.title = @"选择视频";
    } else {
        self.navigationItem.title = _model.name;
    }
    UIButton *rightButton = [UIButton buttonWithType:UIButtonTypeCustom];
    rightButton.frame = CGRectMake(0, 0, 44, 44);
    rightButton.titleLabel.font = [UIFont systemFontOfSize:16];
    [rightButton setTitle:tzImagePickerVc.cancelBtnTitleStr forState:UIControlStateNormal];
    if (_mainColor) {
        [rightButton setTitleColor:_mainColor forState:UIControlStateNormal];
    } else {
        [rightButton setTitleColor:[UIColor colorWithRed:89/255.0 green:182/255.0 blue:215/255.0 alpha:1] forState:UIControlStateNormal];
    }
    [rightButton addTarget:tzImagePickerVc action:@selector(cancelButtonClick) forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:rightButton];
    if (tzImagePickerVc.backImage) {
        [[UINavigationBar appearance] setBackIndicatorImage:tzImagePickerVc.backImage];
        [[UINavigationBar appearance] setBackIndicatorTransitionMaskImage:tzImagePickerVc.backImage];
    }
 
    UIBarButtonItem *backBtnItem = [[UIBarButtonItem alloc] init];
    backBtnItem.title = @"";
    self.navigationItem.backBarButtonItem = backBtnItem;
    _showTakePhotoBtn = (_model.isCameraRoll && tzImagePickerVc.allowTakePicture);
    /// 通过调整返回按钮X轴偏移量,把title移到屏幕外,实现隐藏返回按钮标题的效果
    [[UIBarButtonItem appearance] setBackButtonTitlePositionAdjustment:UIOffsetMake(-100, 0)
                                                         forBarMetrics:UIBarMetricsDefault];
    // [self resetCachedAssets];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didChangeStatusBarOrientationNotification:) name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
}

- (void)fetchAssetModels {
    TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
    if (_isFirstAppear && !_model.models.count) {
        [tzImagePickerVc showProgressHUD];
    }
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (!tzImagePickerVc.sortAscendingByModificationDate && _isFirstAppear && iOS8Later && _model.isCameraRoll) {
            [[TZImageManager manager] getCameraRollAlbum:tzImagePickerVc.allowPickingVideo allowPickingImage:tzImagePickerVc.allowPickingImage needFetchAssets:YES completion:^(TZAlbumModel *model) {
                _model = model;
                
                NSLog(@"%@",_model);
                _models = [NSMutableArray arrayWithArray:_model.models];
                [self initSubviews];
            }];
        } else {
            if (_showTakePhotoBtn || !iOS8Later || _isFirstAppear) {
                [[TZImageManager manager] getAssetsFromFetchResult:_model.result completion:^(NSArray<TZAssetModel *> *models) {
                    _models = [NSMutableArray arrayWithArray:models];
                    [self initSubviews];
                }];
            } else {
                _models = [NSMutableArray arrayWithArray:_model.models];
                [self initSubviews];
            }
        }
    });
}

- (void)initSubviews {
    dispatch_async(dispatch_get_main_queue(), ^{
        TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
        [tzImagePickerVc hideProgressHUD];
        
        [self checkSelectedModels];
        [self configCollectionView];
        _collectionView.hidden = YES;
        [self configBottomToolBar];
        
        [self scrollCollectionViewToBottom];
    });
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
    tzImagePickerVc.isSelectOriginalPhoto = _isSelectOriginalPhoto;
}

- (BOOL)prefersStatusBarHidden {
    return NO;
}

- (void)configCollectionView {
    TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
    
    _layout = [[UICollectionViewFlowLayout alloc] init];
    _collectionView = [[TZCollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:_layout];
    _collectionView.backgroundColor = [UIColor whiteColor];
    _collectionView.dataSource = self;
    _collectionView.delegate = self;
    _collectionView.alwaysBounceHorizontal = NO;
    _collectionView.contentInset = UIEdgeInsetsMake(itemMargin, itemMargin, itemMargin, itemMargin);
    
    if (_showTakePhotoBtn && tzImagePickerVc.allowTakePicture ) {
        _collectionView.contentSize = CGSizeMake(self.view.tz_width, ((_model.count + self.columnNumber) / self.columnNumber) * self.view.tz_width);
    } else {
        _collectionView.contentSize = CGSizeMake(self.view.tz_width, ((_model.count + self.columnNumber - 1) / self.columnNumber) * self.view.tz_width);
    }
    [self.view addSubview:_collectionView];
    [_collectionView registerClass:[TZAssetCell class] forCellWithReuseIdentifier:@"TZAssetCell"];
    [_collectionView registerClass:[TZAssetCameraCell class] forCellWithReuseIdentifier:@"TZAssetCameraCell"];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Determine the size of the thumbnails to request from the PHCachingImageManager
    CGFloat scale = 2.0;
    if ([UIScreen mainScreen].bounds.size.width > 600) {
        scale = 1.0;
    }
    CGSize cellSize = ((UICollectionViewFlowLayout *)_collectionView.collectionViewLayout).itemSize;
    AssetGridThumbnailSize = CGSizeMake(cellSize.width * scale, cellSize.height * scale);
    
    if (!_models) {
        [self fetchAssetModels];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (iOS8Later) {
        // [self updateCachedAssets];
    }
}

- (void)configBottomToolBar {
    TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
    if (!tzImagePickerVc.showSelectBtn) return;

    _bottomToolBar = [[UIView alloc] initWithFrame:CGRectZero];
    CGFloat rgb = 253 / 255.0;
    _bottomToolBar.backgroundColor = [UIColor colorWithRed:rgb green:rgb blue:rgb alpha:1.0];

    _previewButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_previewButton addTarget:self action:@selector(previewButtonClick) forControlEvents:UIControlEventTouchUpInside];
    _previewButton.titleLabel.font = [UIFont systemFontOfSize:16];
    [_previewButton setTitle:tzImagePickerVc.previewBtnTitleStr forState:UIControlStateNormal];
    [_previewButton setTitle:tzImagePickerVc.previewBtnTitleStr forState:UIControlStateDisabled];
    [_previewButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [_previewButton setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];
    _previewButton.enabled = tzImagePickerVc.selectedModels.count;
    
    /*
    if (tzImagePickerVc.allowPickingOriginalPhoto) {
        _originalPhotoButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _originalPhotoButton.imageEdgeInsets = UIEdgeInsetsMake(0, -10, 0, 0);
        [_originalPhotoButton addTarget:self action:@selector(originalPhotoButtonClick) forControlEvents:UIControlEventTouchUpInside];
        _originalPhotoButton.titleLabel.font = [UIFont systemFontOfSize:16];
        [_originalPhotoButton setTitle:tzImagePickerVc.fullImageBtnTitleStr forState:UIControlStateNormal];
        [_originalPhotoButton setTitle:tzImagePickerVc.fullImageBtnTitleStr forState:UIControlStateSelected];
        [_originalPhotoButton setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
        [_originalPhotoButton setTitleColor:[UIColor blackColor] forState:UIControlStateSelected];
        [_originalPhotoButton setImage:[UIImage imageNamedFromMyBundle:tzImagePickerVc.photoOriginDefImageName] forState:UIControlStateNormal];
        [_originalPhotoButton setImage:[UIImage imageNamedFromMyBundle:tzImagePickerVc.photoOriginSelImageName] forState:UIControlStateSelected];
        _originalPhotoButton.selected = _isSelectOriginalPhoto;
        _originalPhotoButton.enabled = tzImagePickerVc.selectedModels.count > 0;
        
        _originalPhotoLabel = [[UILabel alloc] init];
        _originalPhotoLabel.textAlignment = NSTextAlignmentLeft;
        _originalPhotoLabel.font = [UIFont systemFontOfSize:16];
        _originalPhotoLabel.textColor = [UIColor blackColor];
        if (_isSelectOriginalPhoto) [self getSelectedPhotoBytes];
    }
     */
    
    _doneButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _doneButton.titleLabel.font = [UIFont systemFontOfSize:14];
    [_doneButton addTarget:self action:@selector(doneButtonClick) forControlEvents:UIControlEventTouchUpInside];
    [_doneButton setTitle:tzImagePickerVc.doneBtnTitleStr forState:UIControlStateNormal];
    [_doneButton setTitle:tzImagePickerVc.doneBtnTitleStr forState:UIControlStateDisabled];
    [_doneButton setTitleColor:tzImagePickerVc.oKButtonTitleColorNormal forState:UIControlStateNormal];
    [_doneButton setTitleColor:tzImagePickerVc.oKButtonTitleColorDisabled forState:UIControlStateDisabled];
    _doneButton.enabled = tzImagePickerVc.selectedModels.count || tzImagePickerVc.alwaysEnableDoneBtn;
    if ((long)tzImagePickerVc.maxImagesCount > 1) {
        [_doneButton setTitle:[NSString stringWithFormat:@"完成(%ld/%ld)",tzImagePickerVc.selectedModels.count,(long)tzImagePickerVc.maxImagesCount] forState:UIControlStateNormal];
        [_doneButton setTitle:[NSString stringWithFormat:@"完成(%ld/%ld)",tzImagePickerVc.selectedModels.count,(long)tzImagePickerVc.maxImagesCount] forState:UIControlStateDisabled];
        if(tzImagePickerVc.selectedModels.count > 0) {
            _doneButton.backgroundColor = tzImagePickerVc.oKButtonBackGroundColorEnabled;
        } else {
            _doneButton.backgroundColor = tzImagePickerVc.oKButtonBackGroundColorDisabled;
        }
    } else {
        [_doneButton setTitle:@"完成" forState:UIControlStateNormal];
        _doneButton.backgroundColor = tzImagePickerVc.oKButtonBackGroundColorEnabled;
    }
    /*
    _numberImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamedFromMyBundle:tzImagePickerVc.photoNumberIconImageName]];
    _numberImageView.hidden = tzImagePickerVc.selectedModels.count <= 0;
    _numberImageView.backgroundColor = [UIColor clearColor];
    []
    _numberLabel = [[UILabel alloc] init];
    _numberLabel.font = [UIFont systemFontOfSize:15];
    _numberLabel.textColor = [UIColor whiteColor];
    _numberLabel.textAlignment = NSTextAlignmentCenter;
    _numberLabel.text = [NSString stringWithFormat:@"%zd",tzImagePickerVc.selectedModels.count];
    _numberLabel.hidden = tzImagePickerVc.selectedModels.count <= 0;
    _numberLabel.backgroundColor = [UIColor clearColor];
    */
    _divideLine = [[UIView alloc] init];
    CGFloat rgb2 = 235 / 255.0;
    _divideLine.backgroundColor = [UIColor colorWithRed:rgb2 green:rgb2 blue:rgb2 alpha:1.0];
    
    [_bottomToolBar addSubview:_divideLine];
    [_bottomToolBar addSubview:_previewButton];
    [_bottomToolBar addSubview:_doneButton];
//    [_bottomToolBar addSubview:_numberImageView];
//    [_bottomToolBar addSubview:_numberLabel];
//    [_bottomToolBar addSubview:_originalPhotoButton];
    [self.view addSubview:_bottomToolBar];
    [_originalPhotoButton addSubview:_originalPhotoLabel];
}

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
    
    CGFloat top = 0;
    CGFloat collectionViewHeight = 0;
    CGFloat naviBarHeight = self.navigationController.navigationBar.tz_height;
    BOOL isStatusBarHidden = [UIApplication sharedApplication].isStatusBarHidden;
    CGFloat toolBarHeight = [TZCommonTools tz_isIPhoneX] ? 50 + (83 - 49) : 50;
    if (self.navigationController.navigationBar.isTranslucent) {
        top = naviBarHeight;
        if (iOS7Later && !isStatusBarHidden) top += [TZCommonTools tz_statusBarHeight];
        collectionViewHeight = tzImagePickerVc.showSelectBtn ? self.view.tz_height - toolBarHeight - top : self.view.tz_height - top;;
    } else {
        collectionViewHeight = tzImagePickerVc.showSelectBtn ? self.view.tz_height - toolBarHeight : self.view.tz_height;
    }
    _collectionView.frame = CGRectMake(0, top, self.view.tz_width, collectionViewHeight);
    CGFloat itemWH = (self.view.tz_width - (self.columnNumber + 1) * itemMargin) / self.columnNumber;
    _layout.itemSize = CGSizeMake(itemWH, itemWH);
    _layout.minimumInteritemSpacing = itemMargin;
    _layout.minimumLineSpacing = itemMargin;
    [_collectionView setCollectionViewLayout:_layout];
    if (_offsetItemCount > 0) {
        CGFloat offsetY = _offsetItemCount * (_layout.itemSize.height + _layout.minimumLineSpacing);
        [_collectionView setContentOffset:CGPointMake(0, offsetY)];
    }
    
    CGFloat toolBarTop = 0;
    if (!self.navigationController.navigationBar.isHidden) {
        toolBarTop = self.view.tz_height - toolBarHeight;
    } else {
        CGFloat navigationHeight = naviBarHeight;
        if (iOS7Later) navigationHeight += [TZCommonTools tz_statusBarHeight];
        toolBarTop = self.view.tz_height - toolBarHeight - navigationHeight;
    }
    _bottomToolBar.frame = CGRectMake(0, toolBarTop, self.view.tz_width, toolBarHeight);
    CGFloat previewWidth = [tzImagePickerVc.previewBtnTitleStr tz_calculateSizeWithAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:16]} maxSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)].width + 2;
    if (!tzImagePickerVc.allowPreview) {
        previewWidth = 0.0;
    }
    _previewButton.frame = CGRectMake(10, 3, previewWidth, 44);
    _previewButton.tz_width = !tzImagePickerVc.showSelectBtn ? 0 : previewWidth;
    if (tzImagePickerVc.allowPickingOriginalPhoto) {
        CGFloat fullImageWidth = [tzImagePickerVc.fullImageBtnTitleStr tz_calculateSizeWithAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:13]} maxSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)].width;
        _originalPhotoButton.frame = CGRectMake(CGRectGetMaxX(_previewButton.frame), 0, fullImageWidth + 56, 50);
        _originalPhotoLabel.frame = CGRectMake(fullImageWidth + 46, 0, 80, 50);
    }
//    [_doneButton sizeToFit];
    _doneButton.frame = CGRectMake(self.view.tz_width - 80 - 12, (_bottomToolBar.tz_height - 30) / 2.0, 80, 30);
    _doneButton.tz_centerY = _previewButton.tz_centerY;
    _doneButton.layer.cornerRadius = 4;
//    _numberImageView.frame = CGRectMake(_doneButton.tz_left - 30 - 2, 7, 30, 30);
//    _numberLabel.frame = _numberImageView.frame;
    _divideLine.frame = CGRectMake(0, 0, self.view.tz_width, 1);
    
    [TZImageManager manager].columnNumber = [TZImageManager manager].columnNumber;
    [self.collectionView reloadData];
}

#pragma mark - Notification

- (void)didChangeStatusBarOrientationNotification:(NSNotification *)noti {
    _offsetItemCount = _collectionView.contentOffset.y / (_layout.itemSize.height + _layout.minimumLineSpacing);
}

#pragma mark - Click Event
- (void)navLeftBarButtonClick{
    [self.navigationController popViewControllerAnimated:YES];
}
- (void)previewButtonClick {
    TZPhotoPreviewController *photoPreviewVc = [[TZPhotoPreviewController alloc] init];
    [self pushPhotoPrevireViewController:photoPreviewVc];
}

- (void)originalPhotoButtonClick {
    _originalPhotoButton.selected = !_originalPhotoButton.isSelected;
    _isSelectOriginalPhoto = _originalPhotoButton.isSelected;
    _originalPhotoLabel.hidden = !_originalPhotoButton.isSelected;
    if (_isSelectOriginalPhoto) {
        [self getSelectedPhotoBytes];
    }
}

- (void)doneButtonClick {
    TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
    // 1.6.8 判断是否满足最小必选张数的限制
    if (tzImagePickerVc.minImagesCount && tzImagePickerVc.selectedModels.count < tzImagePickerVc.minImagesCount) {
        NSString *title = [NSString stringWithFormat:[NSBundle tz_localizedStringForKey:@"Select a minimum of %zd photos"], tzImagePickerVc.minImagesCount];
        [tzImagePickerVc showAlertWithTitle:title];
        return;
    }
    
    [tzImagePickerVc showProgressHUD];
    NSMutableArray *assets = [NSMutableArray array];
    NSMutableArray *photos;
    NSMutableArray *infoArr;
    if (tzImagePickerVc.onlyReturnAsset) { // not fetch image
        for (NSInteger i = 0; i < tzImagePickerVc.selectedModels.count; i++) {
            TZAssetModel *model = tzImagePickerVc.selectedModels[i];
            [assets addObject:model.asset];
        }
    } else { // fetch image
        photos = [NSMutableArray array];
        infoArr = [NSMutableArray array];
        for (NSInteger i = 0; i < tzImagePickerVc.selectedModels.count; i++) { [photos addObject:@1];[assets addObject:@1];[infoArr addObject:@1]; }
        
        __block BOOL havenotShowAlert = YES;
        [TZImageManager manager].shouldFixOrientation = YES;
        __block id alertView;
        for (NSInteger i = 0; i < tzImagePickerVc.selectedModels.count; i++) {
            TZAssetModel *model = tzImagePickerVc.selectedModels[i];
            [[TZImageManager manager] getPhotoWithAsset:model.asset completion:^(UIImage *photo, NSDictionary *info, BOOL isDegraded) {
                if (isDegraded) return;
                if (photo) {
                    photo = [[TZImageManager manager] scaleImage:photo toSize:CGSizeMake(tzImagePickerVc.photoWidth, (int)(tzImagePickerVc.photoWidth * photo.size.height / photo.size.width))];
                    [photos replaceObjectAtIndex:i withObject:photo];
                }
                if (info)  [infoArr replaceObjectAtIndex:i withObject:info];
                [assets replaceObjectAtIndex:i withObject:model.asset];
                
                for (id item in photos) { if ([item isKindOfClass:[NSNumber class]]) return; }
                
                if (havenotShowAlert) {
                    [tzImagePickerVc hideAlertView:alertView];
                    [self didGetAllPhotos:photos assets:assets infoArr:infoArr];
                }
            } progressHandler:^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {
                // 如果图片正在从iCloud同步中,提醒用户
                if (progress < 1 && havenotShowAlert && !alertView) {
                    [tzImagePickerVc hideProgressHUD];
                    alertView = [tzImagePickerVc showAlertWithTitle:[NSBundle tz_localizedStringForKey:@"Synchronizing photos from iCloud"]];
                    havenotShowAlert = NO;
                    return;
                }
                if (progress >= 1) {
                    havenotShowAlert = YES;
                }
            } networkAccessAllowed:YES];
        }
    }
    if (tzImagePickerVc.selectedModels.count <= 0 || tzImagePickerVc.onlyReturnAsset) {
        [self didGetAllPhotos:photos assets:assets infoArr:infoArr];
    }
}

- (void)didGetAllPhotos:(NSArray *)photos assets:(NSArray *)assets infoArr:(NSArray *)infoArr {
    TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
    [tzImagePickerVc hideProgressHUD];
    
    if (tzImagePickerVc.autoDismiss) {
        [self.navigationController dismissViewControllerAnimated:YES completion:^{
            [self callDelegateMethodWithPhotos:photos assets:assets infoArr:infoArr];
        }];
    } else {
        [self callDelegateMethodWithPhotos:photos assets:assets infoArr:infoArr];
    }
}

- (void)callDelegateMethodWithPhotos:(NSArray *)photos assets:(NSArray *)assets infoArr:(NSArray *)infoArr {
    TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
    if ([tzImagePickerVc.pickerDelegate respondsToSelector:@selector(imagePickerController:didFinishPickingPhotos:sourceAssets:isSelectOriginalPhoto:)]) {
        [tzImagePickerVc.pickerDelegate imagePickerController:tzImagePickerVc didFinishPickingPhotos:photos sourceAssets:assets isSelectOriginalPhoto:_isSelectOriginalPhoto];
    }
    if ([tzImagePickerVc.pickerDelegate respondsToSelector:@selector(imagePickerController:didFinishPickingPhotos:sourceAssets:isSelectOriginalPhoto:infos:)]) {
        [tzImagePickerVc.pickerDelegate imagePickerController:tzImagePickerVc didFinishPickingPhotos:photos sourceAssets:assets isSelectOriginalPhoto:_isSelectOriginalPhoto infos:infoArr];
    }
    if (tzImagePickerVc.didFinishPickingPhotosHandle) {
        tzImagePickerVc.didFinishPickingPhotosHandle(photos,assets,_isSelectOriginalPhoto);
    }
    if (tzImagePickerVc.didFinishPickingPhotosWithInfosHandle) {
        tzImagePickerVc.didFinishPickingPhotosWithInfosHandle(photos,assets,_isSelectOriginalPhoto,infoArr);
    }
}

#pragma mark - UICollectionViewDataSource && Delegate

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    if (_showTakePhotoBtn) {
        TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
        if (tzImagePickerVc.allowPickingImage && tzImagePickerVc.allowTakePicture) {
            return _models.count + 1;
        } else if(tzImagePickerVc.allowPickingVideo == YES) {
            return _models.count + 1;
        }
    }
    return _models.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    // the cell lead to take a picture / 去拍照的cell
    TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
    if (((tzImagePickerVc.sortAscendingByModificationDate && indexPath.row >= _models.count) || (!tzImagePickerVc.sortAscendingByModificationDate && indexPath.row == 0)) && _showTakePhotoBtn) {
        TZAssetCameraCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"TZAssetCameraCell" forIndexPath:indexPath];
        if (tzImagePickerVc.takeVideo) {
            cell.imageView.image = tzImagePickerVc.takeVideo;
        } else {
            cell.imageView.image = [UIImage imageNamedFromMyBundle:tzImagePickerVc.takePictureImageName];
        }
        cell.imageView.backgroundColor = tzImagePickerVc.oKButtonBackGroundColorDisabled;
        return cell;
    }
    // the cell dipaly photo or video / 展示照片或视频的cell
    TZAssetCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"TZAssetCell" forIndexPath:indexPath];
    cell.allowPickingMultipleVideo = tzImagePickerVc.allowPickingMultipleVideo;
    cell.photoDefImageName = tzImagePickerVc.photoDefImageName;
    cell.photoSelImageName = tzImagePickerVc.photoSelImageName;
    cell.selectImage = tzImagePickerVc.selectImage;
    TZAssetModel *model;
    if (tzImagePickerVc.sortAscendingByModificationDate || !_showTakePhotoBtn) {
        model = _models[indexPath.row];
    } else {
        model = _models[indexPath.row - 1];
    }
//    for ( TZAssetModel *tzModel in _model) {
//        NSLog(@"tzModel.isSelected =%d",tzModel.isSelected);
//
    NSLog(@"model.isSelcte===%d", model.isSelected);
    cell.allowPickingGif = tzImagePickerVc.allowPickingGif;
    cell.model = model;
    cell.showSelectBtn = tzImagePickerVc.showSelectBtn;
    cell.allowPreview = tzImagePickerVc.allowPreview;
    
    __weak typeof(cell) weakCell = cell;
    __weak typeof(self) weakSelf = self;
//    __weak typeof(_numberImageView.layer) weakLayer = _numberImageView.layer;
    cell.didSelectPhotoBlock = ^(BOOL isSelected) {
        __strong typeof(weakCell) strongCell = weakCell;
        __strong typeof(weakSelf) strongSelf = weakSelf;
//        __strong typeof(weakLayer) strongLayer = weakLayer;
        TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)strongSelf.navigationController;
        // 1. cancel select / 取消选择
        if (isSelected) {
            strongCell.selectPhotoButton.selected = NO;
            model.isSelected = NO;
            NSArray *selectedModels = [NSArray arrayWithArray:tzImagePickerVc.selectedModels];
            for (TZAssetModel *model_item in selectedModels) {
                if ([[[TZImageManager manager] getAssetIdentifier:model.asset] isEqualToString:[[TZImageManager manager] getAssetIdentifier:model_item.asset]]) {
                    [tzImagePickerVc.selectedModels removeObject:model_item];
                    break;
                }
            }
            [strongSelf refreshBottomToolBarStatus];
        } else {
            // 2. select:check if over the maxImagesCount / 选择照片,检查是否超过了最大个数的限制
            if (tzImagePickerVc.selectedModels.count < tzImagePickerVc.maxImagesCount) {
                strongCell.selectPhotoButton.selected = YES;
                model.isSelected = YES;
                [tzImagePickerVc.selectedModels addObject:model];
                [strongSelf refreshBottomToolBarStatus];
            } else {
                NSString *title = [NSString stringWithFormat:[NSBundle tz_localizedStringForKey:@"Select a maximum of %zd photos"], tzImagePickerVc.maxImagesCount];
                [tzImagePickerVc showAlertWithTitle:title];
            }
        }
//        [UIView showOscillatoryAnimationWithLayer:strongLayer type:TZOscillatoryAnimationToSmaller];
    };
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    // take a photo / 去拍照
    TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
    if (((tzImagePickerVc.sortAscendingByModificationDate && indexPath.row >= _models.count) || (!tzImagePickerVc.sortAscendingByModificationDate && indexPath.row == 0)) && _showTakePhotoBtn)  {
        // 选择短视频的模式，通过代理调起拍照
        // 否则使用系统的拍照
        if (tzImagePickerVc.allowPickingImage == NO && tzImagePickerVc.allowPickingGif == NO && tzImagePickerVc.allowPickingVideo == YES && [tzImagePickerVc.pickerDelegate respondsToSelector:@selector(imagePickerControllerDidClickTakePhotoBtn:)]) {
            [self.navigationController dismissViewControllerAnimated:NO completion:^{
            [tzImagePickerVc.pickerDelegate imagePickerControllerDidClickTakePhotoBtn:tzImagePickerVc];
            }];
        } else {
            [self takePhoto];
        }
        return;
    }
    // preview phote or video / 预览照片或视频
    NSInteger index = indexPath.row;
    if (!tzImagePickerVc.sortAscendingByModificationDate && _showTakePhotoBtn) {
        index = indexPath.row - 1;
    }
    TZAssetModel *model = _models[index];
    if (model.type == TZAssetModelMediaTypeVideo && !tzImagePickerVc.allowPickingMultipleVideo) {
        if (tzImagePickerVc.selectedModels.count > 0) {
            TZImagePickerController *imagePickerVc = (TZImagePickerController *)self.navigationController;
            [imagePickerVc showAlertWithTitle:[NSBundle tz_localizedStringForKey:@"Can not choose both video and photo"]];
        } else {
            // 先判断试是否是低于5min的视频, 同时没有开启直接编辑属性
            // 小于等于5min弹窗提示支持快速上传，以及编辑后上传
            // 大于5min，直接进入编辑页面
            if (self.dontNeedEditVideo) {
                NSLog(@"uploadAction");
                [tzImagePickerVc showProgressHUD];
                // 禁止用户操作
                tzImagePickerVc.view.userInteractionEnabled = NO;
                
                [[PHImageManager defaultManager] requestAVAssetForVideo:model.asset options:nil resultHandler:^(AVAsset * _Nullable asset, AVAudioMix * _Nullable audioMix, NSDictionary * _Nullable info) {
                    if ([asset isKindOfClass:[AVURLAsset class]]) {
                        AVURLAsset *urlAsset = (AVURLAsset*)asset;
                        NSNumber *size;
                        [urlAsset.URL getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
                        /// 默认25mb以下导出最高画质,25以上导出720p中等画质的视频
                        // 默认导出720p中等画质的视频
                        NSString * exportPresetQulity;
                        if (size.longLongValue / (1024.0 * 1024.4) > 25) {
                            exportPresetQulity = AVAssetExportPresetMediumQuality;
                        } else {
                            exportPresetQulity = AVAssetExportPresetHighestQuality;
                        }
                        [[TZImageManager alloc] getVideoOutputPathWithAsset:model.asset presetName:exportPresetQulity version:PHVideoRequestOptionsVersionOriginal success:^(NSString *outputPath) {
                            NSString *exportFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@",@"exportVideo",@"mp4"]];
                            if ([[NSFileManager defaultManager] fileExistsAtPath:exportFilePath]) {
                                // 移除上一个
                                NSError *removeErr;
                                [[NSFileManager defaultManager] removeItemAtPath:exportFilePath error: &removeErr];
                            }
                            // 把文件移动到同一的路径下，修改为同一的名称。方便后续的操作
                            NSError *moveErr;
                            [[NSFileManager defaultManager] moveItemAtURL:[NSURL fileURLWithPath:outputPath] toURL:[NSURL fileURLWithPath:exportFilePath] error:&moveErr];
                            // 获取封面图
                            PHVideoRequestOptions* options = [[PHVideoRequestOptions alloc] init];
                            options.version = PHVideoRequestOptionsVersionOriginal;
                            options.deliveryMode = PHVideoRequestOptionsDeliveryModeAutomatic;
                            options.networkAccessAllowed = YES;
                            [[PHImageManager defaultManager] requestAVAssetForVideo:model.asset options:options resultHandler:^(AVAsset * _Nullable asset, AVAudioMix * _Nullable audioMix, NSDictionary * _Nullable info) {
                                __weak typeof(self) weakSelf = self;
                                AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
                                generator.appliesPreferredTrackTransform = YES;
                                generator.requestedTimeToleranceBefore = kCMTimeZero;
                                generator.requestedTimeToleranceAfter = kCMTimeZero;
                                generator.apertureMode = AVAssetImageGeneratorApertureModeProductionAperture;
                                NSError *error = nil;
                                UIImage *coverImage;
                                
                                CGFloat second = 0;
                                for (int i = 0; i < 5; i ++) {
                                    CGImageRef img = [generator copyCGImageAtTime:CMTimeMake(second * asset.duration.timescale, asset.duration.timescale) actualTime:NULL error:&error];
                                    second = second + 0.2;
                                    if (img != nil) {
                                        coverImage = [UIImage imageWithCGImage:img];
                                        break;
                                    }
                                    NSLog(@"error\n\n -%@", error);
                                }
                                // 允许用户操作
                                tzImagePickerVc.view.userInteractionEnabled = YES;
                                [tzImagePickerVc hideProgressHUD];
                                if (coverImage != nil && exportFilePath != nil) {
                                    /// 切换到主线程
                                    dispatch_sync(dispatch_get_main_queue(), ^{
                                        [tzImagePickerVc dismissViewControllerAnimated:YES completion:^{
                                            if ([tzImagePickerVc.pickerDelegate respondsToSelector:@selector(imagePickerController:didFinishEditVideoCoverImage:videoURL:)]) {
                                                [tzImagePickerVc.pickerDelegate imagePickerController:tzImagePickerVc didFinishEditVideoCoverImage:coverImage videoURL:[NSURL fileURLWithPath:exportFilePath]];
                                            }
                                        }];
                                    });
                                } else {
                                    // 允许用户操作
                                    tzImagePickerVc.view.userInteractionEnabled = YES;
                                    [tzImagePickerVc showAlertWithTitle:@"封面获取出问题啦，请手动编辑"];
                                }
                            }];
                        } failure:^(NSString *errorMessage, NSError *error) {
                            // 允许用户操作
                            tzImagePickerVc.view.userInteractionEnabled = YES;
                            [tzImagePickerVc showAlertWithTitle:@"自动导出出问题啦，请手动编辑"];
                        }];
                    } else {
                        // 允许用户操作
                        tzImagePickerVc.view.userInteractionEnabled = YES;
                        [tzImagePickerVc showAlertWithTitle:@"封面获取出问题啦，请手动编辑"];
                    }
                }];
                return;
            }
            NSArray *timeArr = [model.timeLength componentsSeparatedByString:@":"];
            if (timeArr.count == 2 && (([timeArr[1] integerValue] == 0 && [timeArr[0] integerValue] <= 5) || ([timeArr[1] integerValue] > 0 && [timeArr[0] integerValue] <= 4)) && tzImagePickerVc.directEditVideo == false) {
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"" message:@"温馨提示" preferredStyle:UIAlertControllerStyleActionSheet];
                [alertController.view setTintColor:UIColor.blackColor];
                UIAlertAction *uploadAction = [UIAlertAction actionWithTitle:@"快速上传(支持5分钟以内)" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    NSLog(@"uploadAction");
                    [tzImagePickerVc showProgressHUD];
                    // 禁止用户操作
                    tzImagePickerVc.view.userInteractionEnabled = NO;

                    [[PHImageManager defaultManager] requestAVAssetForVideo:model.asset options:nil resultHandler:^(AVAsset * _Nullable asset, AVAudioMix * _Nullable audioMix, NSDictionary * _Nullable info) {
                        if ([asset isKindOfClass:[AVURLAsset class]]) {
                            AVURLAsset *urlAsset = (AVURLAsset*)asset;
                            NSNumber *size;
                            [urlAsset.URL getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
                            /// 默认25mb以下导出最高画质,25以上导出720p中等画质的视频
                            // 默认导出720p中等画质的视频
                            NSString * exportPresetQulity;
                            if (size.longLongValue / (1024.0 * 1024.4) > 25) {
                                exportPresetQulity = AVAssetExportPresetMediumQuality;
                            } else {
                                exportPresetQulity = AVAssetExportPresetHighestQuality;
                            }
                            [[TZImageManager alloc] getVideoOutputPathWithAsset:model.asset presetName:exportPresetQulity version:PHVideoRequestOptionsVersionOriginal success:^(NSString *outputPath) {
                                NSString *exportFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@",@"exportVideo",@"mp4"]];
                                if ([[NSFileManager defaultManager] fileExistsAtPath:exportFilePath]) {
                                    // 移除上一个
                                    NSError *removeErr;
                                    [[NSFileManager defaultManager] removeItemAtPath:exportFilePath error: &removeErr];
                                }
                                // 把文件移动到同一的路径下，修改为同一的名称。方便后续的操作
                                NSError *moveErr;
                                [[NSFileManager defaultManager] moveItemAtURL:[NSURL fileURLWithPath:outputPath] toURL:[NSURL fileURLWithPath:exportFilePath] error:&moveErr];
                                // 获取封面图
                                PHVideoRequestOptions* options = [[PHVideoRequestOptions alloc] init];
                                options.version = PHVideoRequestOptionsVersionOriginal;
                                options.deliveryMode = PHVideoRequestOptionsDeliveryModeAutomatic;
                                options.networkAccessAllowed = YES;
                                [[PHImageManager defaultManager] requestAVAssetForVideo:model.asset options:options resultHandler:^(AVAsset * _Nullable asset, AVAudioMix * _Nullable audioMix, NSDictionary * _Nullable info) {
                                    __weak typeof(self) weakSelf = self;
                                    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
                                    generator.appliesPreferredTrackTransform = YES;
                                    generator.requestedTimeToleranceBefore = kCMTimeZero;
                                    generator.requestedTimeToleranceAfter = kCMTimeZero;
                                    generator.apertureMode = AVAssetImageGeneratorApertureModeProductionAperture;
                                    NSError *error = nil;
                                    UIImage *coverImage;
                                    
                                    CGFloat second = 0;
                                    for (int i = 0; i < 5; i ++) {
                                        CGImageRef img = [generator copyCGImageAtTime:CMTimeMake(second * asset.duration.timescale, asset.duration.timescale) actualTime:NULL error:&error];
                                        second = second + 0.2;
                                        if (img != nil) {
                                            coverImage = [UIImage imageWithCGImage:img];
                                            break;
                                        }
                                        NSLog(@"error\n\n -%@", error);
                                    }
                                    // 允许用户操作
                                    tzImagePickerVc.view.userInteractionEnabled = YES;
                                    [tzImagePickerVc hideProgressHUD];
                                    if (coverImage != nil && exportFilePath != nil) {
                                        /// 切换到主线程
                                        dispatch_sync(dispatch_get_main_queue(), ^{
                                            [tzImagePickerVc dismissViewControllerAnimated:YES completion:^{
                                                if ([tzImagePickerVc.pickerDelegate respondsToSelector:@selector(imagePickerController:didFinishEditVideoCoverImage:videoURL:)]) {
                                                    [tzImagePickerVc.pickerDelegate imagePickerController:tzImagePickerVc didFinishEditVideoCoverImage:coverImage videoURL:[NSURL fileURLWithPath:exportFilePath]];
                                                }
                                            }];
                                        });
                                    } else {
                                        // 允许用户操作
                                        tzImagePickerVc.view.userInteractionEnabled = YES;
                                        [tzImagePickerVc showAlertWithTitle:@"封面获取出问题啦，请手动编辑"];
                                    }
                                }];
                            } failure:^(NSString *errorMessage, NSError *error) {
                                // 允许用户操作
                                tzImagePickerVc.view.userInteractionEnabled = YES;
                                [tzImagePickerVc showAlertWithTitle:@"自动导出出问题啦，请手动编辑"];
                            }];
                        } else {
                            // 允许用户操作
                            tzImagePickerVc.view.userInteractionEnabled = YES;
                            [tzImagePickerVc showAlertWithTitle:@"封面获取出问题啦，请手动编辑"];
                        }
                    }];
                }];
                UIAlertAction *editAction = [UIAlertAction actionWithTitle:@"编辑后上传" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    NSLog(@"editAction");
                    TZImagePickerController *imagePickerVc = (TZImagePickerController *)self.navigationController;
                    ZLEditVideoController *editVC = [[ZLEditVideoController alloc]init];
                    if (imagePickerVc.videoEditVCbackImage) {
                        editVC.backImage = imagePickerVc.videoEditVCbackImage;
                    }
                    if (imagePickerVc.mainColor) {
                        editVC.mainColor = imagePickerVc.mainColor;
                    }
                    if (imagePickerVc.maxEditVideoTime > 0) {
                        editVC.maxEditVideoTime = imagePickerVc.maxEditVideoTime;
                    }
                    if (imagePickerVc.minEditVideoTime > 0) {
                        editVC.minEditVideoTime = imagePickerVc.minEditVideoTime;
                    }
                    editVC.asset = model.asset;
                    editVC.coverImageBlock = ^(UIImage *coverImage, NSURL *videoPath) {
                        [imagePickerVc dismissViewControllerAnimated:YES completion:^{
                            if (coverImage != nil && videoPath != nil) {
                                if ([imagePickerVc.pickerDelegate respondsToSelector:@selector(imagePickerController:didFinishEditVideoCoverImage:videoURL:)]) {
                                    [imagePickerVc.pickerDelegate imagePickerController:imagePickerVc didFinishEditVideoCoverImage:coverImage videoURL:videoPath];
                                }
                            }
                        }];
                    };
                    [self.navigationController pushViewController:editVC animated:YES];
                }];
                UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                    NSLog(@"cancel");
                }];
                [alertController addAction:uploadAction];
                [alertController addAction:editAction];
                [alertController addAction:cancelAction];
                [self presentViewController:alertController animated:YES completion:nil];
            } else {
                TZImagePickerController *imagePickerVc = (TZImagePickerController *)self.navigationController;
                ZLEditVideoController *editVC = [[ZLEditVideoController alloc]init];
                if (imagePickerVc.videoEditVCbackImage) {
                    editVC.backImage = imagePickerVc.videoEditVCbackImage;
                }
                if (imagePickerVc.mainColor) {
                    editVC.mainColor = imagePickerVc.mainColor;
                }
                if (imagePickerVc.maxEditVideoTime > 0) {
                    editVC.maxEditVideoTime = imagePickerVc.maxEditVideoTime;
                }
                if (imagePickerVc.minEditVideoTime > 0) {
                    editVC.minEditVideoTime = imagePickerVc.minEditVideoTime;
                }
                editVC.asset = model.asset;
                editVC.coverImageBlock = ^(UIImage *coverImage, NSURL *videoPath) {
                    [imagePickerVc dismissViewControllerAnimated:YES completion:^{
                        if (coverImage != nil && videoPath != nil) {
                            if ([imagePickerVc.pickerDelegate respondsToSelector:@selector(imagePickerController:didFinishEditVideoCoverImage:videoURL:)]) {
                                [imagePickerVc.pickerDelegate imagePickerController:imagePickerVc didFinishEditVideoCoverImage:coverImage videoURL:videoPath];
                            }
                        }
                    }];
                };
                [self.navigationController pushViewController:editVC animated:YES];
            }
            return;
            // TODO: 后续如果需要修改代码和旧代码共存,增进一个协议函数返回Bool值决定是否调整即可
            [[TZImageManager manager] getPhotoWithAsset:model.asset completion:^(UIImage *photo, NSDictionary *info, BOOL isDegraded) {
                if (!isDegraded && photo) {
                    TZImagePickerController *imagePickerVc = (TZImagePickerController *)self.navigationController;
                    if (self.navigationController) {
                        [self.navigationController dismissViewControllerAnimated:NO completion:^{
                            if ([imagePickerVc.pickerDelegate respondsToSelector:@selector(imagePickerController:didFinishPickingVideo:sourceAssets:)]) {
                                [imagePickerVc.pickerDelegate imagePickerController:imagePickerVc didFinishPickingVideo:photo sourceAssets:model.asset];
                            }
                            if (imagePickerVc.didFinishPickingVideoHandle) {
                                imagePickerVc.didFinishPickingVideoHandle(photo,model.asset);
                            }
                        }];
                    }
                }
            }];
        }
    } else if (model.type == TZAssetModelMediaTypePhotoGif && tzImagePickerVc.allowPickingGif && !tzImagePickerVc.allowPickingMultipleVideo) {
        if (tzImagePickerVc.selectedModels.count > 0) {
            TZImagePickerController *imagePickerVc = (TZImagePickerController *)self.navigationController;
            [imagePickerVc showAlertWithTitle:[NSBundle tz_localizedStringForKey:@"Can not choose both photo and GIF"]];
        } else {
            TZGifPhotoPreviewController *gifPreviewVc = [[TZGifPhotoPreviewController alloc] init];
            gifPreviewVc.model = model;
            UIBarButtonItem *backBtnItem = [[UIBarButtonItem alloc] init];
            backBtnItem.title = @" ";
            self.navigationItem.backBarButtonItem = backBtnItem;
            [self.navigationController pushViewController:gifPreviewVc animated:YES];
        }
    } else {
        TZImagePickerController *imagePickerVc = (TZImagePickerController *)self.navigationController;
        if (imagePickerVc.shouldPick) {
            TZAssetModel *asset = _models[index];
            TZImagePickerController *imagePickerVc = (TZImagePickerController *)self.navigationController;
            [[TZImageManager manager] getOriginalPhotoWithAsset:asset.asset completion:^(UIImage *photo, NSDictionary *info) {
                LZImageCropping *imageBrowser = [[LZImageCropping alloc]init];
                TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
                //设置代理
                imageBrowser.delegate = self;
                if (tzImagePickerVc.isSquare) {
                    imageBrowser.cropSize = CGSizeMake(UIScreen.mainScreen.bounds.size.width - 80, UIScreen.mainScreen.bounds.size.width - 80);
                } else {
                    imageBrowser.cropSize = CGSizeMake(UIScreen.mainScreen.bounds.size.width, UIScreen.mainScreen.bounds.size.width / 2.0);
                }
                [imageBrowser setImage:photo];
                imageBrowser.titleLabel.text = tzImagePickerVc.topTitle;
                imageBrowser.backImage = imagePickerVc.backImage;
                //设置自定义裁剪区域大小
                //是否需要圆形
                imageBrowser.isRound = NO;
                if (_mainColor) {
                    imageBrowser.mainColor = _mainColor;
                }
                [self.navigationController pushViewController:imageBrowser animated:YES];
            }];
        } else {
            TZPhotoPreviewController *photoPreviewVc = [[TZPhotoPreviewController alloc] init];
            photoPreviewVc.currentIndex = index;
            photoPreviewVc.models = _models;
            [self pushPhotoPrevireViewController:photoPreviewVc];
        }
    }
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (iOS8Later) {
        // [self updateCachedAssets];
    }
}

#pragma mark - LZImageCroppingDelegate
- (void)lzImageCropping:(LZImageCropping *)cropping didCropImage:(UIImage *)image {
    [self didGetAllPhotos:@[image] assets:nil infoArr:nil];
}

#pragma mark - Private Method

/// 拍照按钮点击事件
- (void)takePhoto {
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if ((authStatus == AVAuthorizationStatusRestricted || authStatus ==AVAuthorizationStatusDenied) && iOS7Later) {
        
        NSDictionary *infoDict = [TZCommonTools tz_getInfoDictionary];
        // 无权限 做一个友好的提示
        NSString *appName = [infoDict valueForKey:@"CFBundleDisplayName"];
        if (!appName) appName = [infoDict valueForKey:@"CFBundleName"];
        
        NSString *message = [NSString stringWithFormat:[NSBundle tz_localizedStringForKey:@"Please allow %@ to access your camera in \"Settings -> Privacy -> Camera\""],appName];
        if (iOS8Later) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:[NSBundle tz_localizedStringForKey:@"Can not use camera"] message:message delegate:self cancelButtonTitle:[NSBundle tz_localizedStringForKey:@"Cancel"] otherButtonTitles:[NSBundle tz_localizedStringForKey:@"Setting"], nil];
            [alert show];
        } else {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:[NSBundle tz_localizedStringForKey:@"Can not use camera"] message:message delegate:self cancelButtonTitle:[NSBundle tz_localizedStringForKey:@"OK"] otherButtonTitles:nil];
            [alert show];
        }
    } else if (authStatus == AVAuthorizationStatusNotDetermined) {
        // fix issue 466, 防止用户首次拍照拒绝授权时相机页黑屏
        if (iOS7Later) {
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                if (granted) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self pushImagePickerController];
                    });
                }
            }];
        } else {
            [self pushImagePickerController];
        }
    } else {
        [self pushImagePickerController];
    }
}

// 调用相机
- (void)pushImagePickerController {
    // 提前定位
    __weak typeof(self) weakSelf = self;
    [[TZLocationManager manager] startLocationWithSuccessBlock:^(NSArray<CLLocation *> *locations) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.location = [locations firstObject];
    } failureBlock:^(NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.location = nil;
    }];
    
    UIImagePickerControllerSourceType sourceType = UIImagePickerControllerSourceTypeCamera;
    if ([UIImagePickerController isSourceTypeAvailable: UIImagePickerControllerSourceTypeCamera]) {
        self.imagePickerVc.sourceType = sourceType;
        if(iOS8Later) {
            _imagePickerVc.modalPresentationStyle = UIModalPresentationOverCurrentContext;
        }
        [self presentViewController:_imagePickerVc animated:YES completion:nil];
    } else {
        NSLog(@"模拟器中无法打开照相机,请在真机中使用");
    }
}

- (void)refreshBottomToolBarStatus {
    TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
    
    _previewButton.enabled = tzImagePickerVc.selectedModels.count > 0;
    _doneButton.enabled = tzImagePickerVc.selectedModels.count > 0 || tzImagePickerVc.alwaysEnableDoneBtn;
    
//    _numberImageView.hidden = tzImagePickerVc.selectedModels.count <= 0;
//    _numberLabel.hidden = tzImagePickerVc.selectedModels.count <= 0;
//    _numberLabel.text = [NSString stringWithFormat:@"%zd",tzImagePickerVc.selectedModels.count];
    if ((long)tzImagePickerVc.maxImagesCount > 1) {
        [_doneButton setTitle:[NSString stringWithFormat:@"完成(%ld/%ld)",tzImagePickerVc.selectedModels.count,(long)tzImagePickerVc.maxImagesCount] forState:UIControlStateNormal];
        if(tzImagePickerVc.selectedModels.count > 0) {
            _doneButton.backgroundColor = tzImagePickerVc.oKButtonBackGroundColorEnabled;
        } else {
            _doneButton.backgroundColor = tzImagePickerVc.oKButtonBackGroundColorDisabled;
               [_doneButton setTitle:[NSString stringWithFormat:@"完成(%d/%ld)",0,(long)tzImagePickerVc.maxImagesCount] forState:UIControlStateDisabled];
        }
    } else {
        [_doneButton setTitle:@"完成" forState:UIControlStateNormal];
        _doneButton.backgroundColor = tzImagePickerVc.oKButtonBackGroundColorEnabled;
        
    }
    _originalPhotoButton.enabled = tzImagePickerVc.selectedModels.count > 0;
    _originalPhotoButton.selected = (_isSelectOriginalPhoto && _originalPhotoButton.enabled);
    _originalPhotoLabel.hidden = (!_originalPhotoButton.isSelected);
    if (_isSelectOriginalPhoto) [self getSelectedPhotoBytes];
}

- (void)pushPhotoPrevireViewController:(TZPhotoPreviewController *)photoPreviewVc {
    __weak typeof(self) weakSelf = self;
    photoPreviewVc.isSelectOriginalPhoto = _isSelectOriginalPhoto;
    [photoPreviewVc setBackButtonClickBlock:^(BOOL isSelectOriginalPhoto) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.isSelectOriginalPhoto = isSelectOriginalPhoto;
        [strongSelf.collectionView reloadData];
        [strongSelf refreshBottomToolBarStatus];
    }];
    [photoPreviewVc setDoneButtonClickBlock:^(BOOL isSelectOriginalPhoto) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.isSelectOriginalPhoto = isSelectOriginalPhoto;
        [strongSelf doneButtonClick];
    }];
    [photoPreviewVc setDoneButtonClickBlockCropMode:^(UIImage *cropedImage, id asset) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf didGetAllPhotos:@[cropedImage] assets:@[asset] infoArr:nil];
    }];
    [self.navigationController pushViewController:photoPreviewVc animated:YES];
}

- (void)getSelectedPhotoBytes {
    // 越南语 && 5屏幕时会显示不下，暂时这样处理
    if ([[TZImagePickerConfig sharedInstance].preferredLanguage isEqualToString:@"vi"] && self.view.tz_width <= 320) {
        return;
    }
    TZImagePickerController *imagePickerVc = (TZImagePickerController *)self.navigationController;
    [[TZImageManager manager] getPhotosBytesWithArray:imagePickerVc.selectedModels completion:^(NSString *totalBytes) {
        _originalPhotoLabel.text = [NSString stringWithFormat:@"(%@)",totalBytes];
    }];
}

- (void)scrollCollectionViewToBottom {
    TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
    if (_shouldScrollToBottom && _models.count > 0) {
        NSInteger item = 0;
        if (tzImagePickerVc.sortAscendingByModificationDate) {
            item = _models.count - 1;
            if (_showTakePhotoBtn) {
                TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
                if (tzImagePickerVc.allowPickingImage && tzImagePickerVc.allowTakePicture) {
                    item += 1;
                }
            }
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [_collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:item inSection:0] atScrollPosition:UICollectionViewScrollPositionBottom animated:NO];
            _shouldScrollToBottom = NO;
            _collectionView.hidden = NO;
        });
    } else {
        _collectionView.hidden = NO;
    }
}

- (void)checkSelectedModels {
    NSMutableArray *selectedAssets = [NSMutableArray array];
    TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
    for (TZAssetModel *model in tzImagePickerVc.selectedModels) {
        [selectedAssets addObject:model.asset];
    }
    for (TZAssetModel *model in _models) {
        model.isSelected = NO;
        if ([[TZImageManager manager] isAssetsArray:selectedAssets containAsset:model.asset]) {
            model.isSelected = YES;
        }
    }
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 1) { // 去设置界面，开启相机访问权限
        if (iOS8Later) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
        }
    }
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController*)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSString *type = [info objectForKey:UIImagePickerControllerMediaType];
    if ([type isEqualToString:@"public.image"]) {
        TZImagePickerController *imagePickerVc = (TZImagePickerController *)self.navigationController;
        [imagePickerVc showProgressHUD];
        UIImage *photo = [info objectForKey:UIImagePickerControllerOriginalImage];
        if (photo) {
            [[TZImageManager manager] savePhotoWithImage:photo location:self.location completion:^(NSError *error){
                if (!error) {
                    [self reloadPhotoArray];
                }
            }];
            self.location = nil;
        }
    }
}

- (void)reloadPhotoArray {
    TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
    [[TZImageManager manager] getCameraRollAlbum:tzImagePickerVc.allowPickingVideo allowPickingImage:tzImagePickerVc.allowPickingImage needFetchAssets:NO completion:^(TZAlbumModel *model) {
        _model = model;
        [[TZImageManager manager] getAssetsFromFetchResult:_model.result completion:^(NSArray<TZAssetModel *> *models) {
            [tzImagePickerVc hideProgressHUD];
            
            TZAssetModel *assetModel;
            if (tzImagePickerVc.sortAscendingByModificationDate) {
                assetModel = [models lastObject];
                [_models addObject:assetModel];
            } else {
                assetModel = [models firstObject];
                [_models insertObject:assetModel atIndex:0];
            }
            
            if (tzImagePickerVc.maxImagesCount <= 1) {
                if (tzImagePickerVc.shouldPick) {
                    TZAssetModel *asset;
                    if (tzImagePickerVc.sortAscendingByModificationDate) {
                        asset = _models[_models.count - 1];
                    } else {
                        asset = _models[0];
                    }
                    [[TZImageManager manager] getOriginalPhotoWithAsset:asset.asset completion:^(UIImage *photo, NSDictionary *info) {
                        LZImageCropping *imageBrowser = [[LZImageCropping alloc]init];
                        TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
                        //设置代理
                        imageBrowser.delegate = self;
                        if (tzImagePickerVc.isSquare) {
                            imageBrowser.cropSize = CGSizeMake(UIScreen.mainScreen.bounds.size.width - 80, UIScreen.mainScreen.bounds.size.width - 80);
                        } else {
                            imageBrowser.cropSize = CGSizeMake(UIScreen.mainScreen.bounds.size.width, UIScreen.mainScreen.bounds.size.width / 2.0);
                        }
                        imageBrowser.titleLabel.text = tzImagePickerVc.topTitle;
                        [imageBrowser setImage:photo];
                        //设置自定义裁剪区域大小
                        //是否需要圆形
                        imageBrowser.isRound = NO;
                        if (_mainColor) {
                            imageBrowser.mainColor = _mainColor;
                        }
                        [self presentViewController:imageBrowser animated:YES completion:nil];
                    }];
                } else {
                    if (tzImagePickerVc.allowCrop) {
                        TZPhotoPreviewController *photoPreviewVc = [[TZPhotoPreviewController alloc] init];
                        if (tzImagePickerVc.sortAscendingByModificationDate) {
                            photoPreviewVc.currentIndex = _models.count - 1;
                        } else {
                            photoPreviewVc.currentIndex = 0;
                        }
                        photoPreviewVc.models = _models;
                        [self pushPhotoPrevireViewController:photoPreviewVc];
                    } else {
                        [tzImagePickerVc.selectedModels addObject:assetModel];
                        [self doneButtonClick];
                    }
                }
                return;
            }
            
            if (tzImagePickerVc.selectedModels.count < tzImagePickerVc.maxImagesCount) {
                assetModel.isSelected = YES;
                [tzImagePickerVc.selectedModels addObject:assetModel];
                [self refreshBottomToolBarStatus];
            }
            _collectionView.hidden = YES;
            [_collectionView reloadData];
            
            _shouldScrollToBottom = YES;
            [self scrollCollectionViewToBottom];
        }];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)dealloc {
    // NSLog(@"%@ dealloc",NSStringFromClass(self.class));
}

#pragma mark - Asset Caching

- (void)resetCachedAssets {
    [[TZImageManager manager].cachingImageManager stopCachingImagesForAllAssets];
    self.previousPreheatRect = CGRectZero;
}

- (void)updateCachedAssets {
    BOOL isViewVisible = [self isViewLoaded] && [[self view] window] != nil;
    if (!isViewVisible) { return; }
    
    // The preheat window is twice the height of the visible rect.
    CGRect preheatRect = _collectionView.bounds;
    preheatRect = CGRectInset(preheatRect, 0.0f, -0.5f * CGRectGetHeight(preheatRect));
    
    /*
     Check if the collection view is showing an area that is significantly
     different to the last preheated area.
     */
    CGFloat delta = ABS(CGRectGetMidY(preheatRect) - CGRectGetMidY(self.previousPreheatRect));
    if (delta > CGRectGetHeight(_collectionView.bounds) / 3.0f) {
        
        // Compute the assets to start caching and to stop caching.
        NSMutableArray *addedIndexPaths = [NSMutableArray array];
        NSMutableArray *removedIndexPaths = [NSMutableArray array];
        
        [self computeDifferenceBetweenRect:self.previousPreheatRect andRect:preheatRect removedHandler:^(CGRect removedRect) {
            NSArray *indexPaths = [self aapl_indexPathsForElementsInRect:removedRect];
            [removedIndexPaths addObjectsFromArray:indexPaths];
        } addedHandler:^(CGRect addedRect) {
            NSArray *indexPaths = [self aapl_indexPathsForElementsInRect:addedRect];
            [addedIndexPaths addObjectsFromArray:indexPaths];
        }];
        
        NSArray *assetsToStartCaching = [self assetsAtIndexPaths:addedIndexPaths];
        NSArray *assetsToStopCaching = [self assetsAtIndexPaths:removedIndexPaths];
        
        // Update the assets the PHCachingImageManager is caching.
        [[TZImageManager manager].cachingImageManager startCachingImagesForAssets:assetsToStartCaching
                                                                       targetSize:AssetGridThumbnailSize
                                                                      contentMode:PHImageContentModeAspectFill
                                                                          options:nil];
        [[TZImageManager manager].cachingImageManager stopCachingImagesForAssets:assetsToStopCaching
                                                                      targetSize:AssetGridThumbnailSize
                                                                     contentMode:PHImageContentModeAspectFill
                                                                         options:nil];
        
        // Store the preheat rect to compare against in the future.
        self.previousPreheatRect = preheatRect;
    }
}

- (void)computeDifferenceBetweenRect:(CGRect)oldRect andRect:(CGRect)newRect removedHandler:(void (^)(CGRect removedRect))removedHandler addedHandler:(void (^)(CGRect addedRect))addedHandler {
    if (CGRectIntersectsRect(newRect, oldRect)) {
        CGFloat oldMaxY = CGRectGetMaxY(oldRect);
        CGFloat oldMinY = CGRectGetMinY(oldRect);
        CGFloat newMaxY = CGRectGetMaxY(newRect);
        CGFloat newMinY = CGRectGetMinY(newRect);
        
        if (newMaxY > oldMaxY) {
            CGRect rectToAdd = CGRectMake(newRect.origin.x, oldMaxY, newRect.size.width, (newMaxY - oldMaxY));
            addedHandler(rectToAdd);
        }
        
        if (oldMinY > newMinY) {
            CGRect rectToAdd = CGRectMake(newRect.origin.x, newMinY, newRect.size.width, (oldMinY - newMinY));
            addedHandler(rectToAdd);
        }
        
        if (newMaxY < oldMaxY) {
            CGRect rectToRemove = CGRectMake(newRect.origin.x, newMaxY, newRect.size.width, (oldMaxY - newMaxY));
            removedHandler(rectToRemove);
        }
        
        if (oldMinY < newMinY) {
            CGRect rectToRemove = CGRectMake(newRect.origin.x, oldMinY, newRect.size.width, (newMinY - oldMinY));
            removedHandler(rectToRemove);
        }
    } else {
        addedHandler(newRect);
        removedHandler(oldRect);
    }
}

- (NSArray *)assetsAtIndexPaths:(NSArray *)indexPaths {
    if (indexPaths.count == 0) { return nil; }
    
    NSMutableArray *assets = [NSMutableArray arrayWithCapacity:indexPaths.count];
    for (NSIndexPath *indexPath in indexPaths) {
        if (indexPath.item < _models.count) {
            TZAssetModel *model = _models[indexPath.item];
            [assets addObject:model.asset];
        }
    }
    
    return assets;
}

- (NSArray *)aapl_indexPathsForElementsInRect:(CGRect)rect {
    NSArray *allLayoutAttributes = [_collectionView.collectionViewLayout layoutAttributesForElementsInRect:rect];
    if (allLayoutAttributes.count == 0) { return nil; }
    NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:allLayoutAttributes.count];
    for (UICollectionViewLayoutAttributes *layoutAttributes in allLayoutAttributes) {
        NSIndexPath *indexPath = layoutAttributes.indexPath;
        [indexPaths addObject:indexPath];
    }
    return indexPaths;
}
#pragma clang diagnostic pop

@end



@implementation TZCollectionView

- (BOOL)touchesShouldCancelInContentView:(UIView *)view {
    if ([view isKindOfClass:[UIControl class]]) {
        return YES;
    }
    return [super touchesShouldCancelInContentView:view];
}

@end
