//
//  CXDragTableView.m
//  drawTableViewCell
//
//  Created by caixiang on 2019/9/10.
//  Copyright © 2019 蔡翔. All rights reserved.
//

#import "CXDragTableView.h"

typedef enum{
    SnapshotMeetsEdgeTop = 1,
    SnapshotMeetsEdgeBottom,
}SnapshotMeetsEdge;

@interface CXDragTableView ()

#pragma mark - Data Perproty
@property (nonatomic, strong) UILongPressGestureRecognizer *gesture;
@property (nonatomic, strong) NSIndexPath *selectedIndexPath;
@property (nonatomic, strong) NSIndexPath *touchIndexPath;
@property (nonatomic, strong) UIView *dragView;
@property (nonatomic, strong) CADisplayLink *autoScrollTimer;
@property (nonatomic, assign) SnapshotMeetsEdge autoScrollDirection;
@property (nonatomic, assign) BOOL canDrag;
@property (strong, nonatomic) NSIndexPath *gestureRecognizerStateChangedExchangeIndex;;

#pragma mark - UI Perproty

@end

@implementation CXDragTableView

@dynamic dataSource, delegate;

#pragma mark - life Cycle
- (instancetype)initWithFrame:(CGRect)frame style:(UITableViewStyle)style
{
    self = [super initWithFrame:frame style:style];
    if (self) {
        [self initData];
        [self addGesture];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self initData];
        [self addGesture];
    }
    return self;
}

#pragma mark - private
- (void)initData {
    _canDrag = YES;
}

- (void)addGesture {
    _gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(processGesture:)];
    _gesture.minimumPressDuration = 0.3;
    [self addGestureRecognizer:_gesture];
}

- (void)processGesture:(UILongPressGestureRecognizer *)gesture {
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
        {
//            NSLog(@"UIGestureRecognizerStateBegan");
            CGPoint point = [gesture locationInView:gesture.view];
            NSIndexPath *selectedIndexPath = [self indexPathForRowAtPoint:point];
            self.touchIndexPath = selectedIndexPath;
            if (!selectedIndexPath) {
                return;
            }
            self.selectedIndexPath = selectedIndexPath;

            if(self.delegate && [self.delegate respondsToSelector:@selector(tableView:newCanMoveRowAtIndexPath:)]) {
               _canDrag = [self.delegate tableView:self newCanMoveRowAtIndexPath:selectedIndexPath];
            }
            if (!_canDrag) {
                return;
            }
            
            //把自定义的cell样式给外界自定义
             UITableViewCell *cell = [self cellForRowAtIndexPath:selectedIndexPath];
            if (self.delegate &&[self.delegate respondsToSelector:@selector(tableView:willMoveCellAtIndexPath:processCell:)]) {
                [self.delegate tableView:self willMoveCellAtIndexPath:selectedIndexPath processCell:cell];
            }
            self.dragView = [self snapshotViewWithInputView:cell];
            self.dragView.frame = cell.frame;
            [self addSubview:self.dragView];
            cell.hidden = YES;
            [UIView animateWithDuration:0.15 animations:^{
                self.dragView.transform = CGAffineTransformScale(self.
                                                                 dragView.transform, 1.005, 1.008);
                self.dragView.alpha = 0.9;
                self.dragView.center = CGPointMake(self.dragView.center.x, point.y);
            }];
        }
            break;
        case UIGestureRecognizerStateChanged:
        {
//            NSLog(@"UIGestureRecognizerStateChanged");
            //拖拽的时候的区域可能是超出了拖拽区域
            if (!self.touchIndexPath) {
                return;
            }
            if(self.delegate && [self.delegate respondsToSelector:@selector(tableView:newCanMoveRowAtIndexPath:)]) {
                _canDrag = [self.delegate tableView:self newCanMoveRowAtIndexPath:self.selectedIndexPath];
            }
            if (!_canDrag) {
                return;
            }
            //正在拽的cell永远是隐藏的 解决复用的时候会重新出现的bug
            UITableViewCell *cell = [self cellForRowAtIndexPath:self.selectedIndexPath];
            cell.hidden = YES;
            
            CGPoint point = [gesture locationInView:gesture.view];
            CGPoint center  = self.dragView.center;
            center.y = point.y;
            self.dragView.center = center;
            
            NSIndexPath *exchangeIndex = [self indexPathForRowAtPoint:point];
            _gestureRecognizerStateChangedExchangeIndex = exchangeIndex;
            
            if ([self checkIfSnapshotMeetsEdge]) {
                [self startAutoScrollTimer];
//                NSLog(@"🔥startAutoScrollTimer");
                return;
            }else{
                [self stopAutoScrollTimer];
//                NSLog(@"🚀stopAutoScrollTimer");
            }
            
            if (exchangeIndex) {
                //判断下要移动的exchangeIndex 是否是在允许的范围内
                BOOL canExchange = YES;
                if (self.delegate && [self.delegate respondsToSelector:@selector(tableView:newTargetIndexPathForMoveFromRowAtIndexPath:toProposedIndexPath:)]) {
                    canExchange = [self.delegate tableView:self newTargetIndexPathForMoveFromRowAtIndexPath:self.selectedIndexPath toProposedIndexPath:exchangeIndex];
                }
                if (!canExchange) {//不能移动到指定范围
                    [self updateDataWithIndexPath:self.selectedIndexPath];
                    return;
                }
                [self updateDataWithIndexPath:exchangeIndex];
                [self moveRowAtIndexPath:self.selectedIndexPath toIndexPath:exchangeIndex];
                self.selectedIndexPath = exchangeIndex;
            }
        }
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        {
//            NSLog(@"UIGestureRecognizerStateCancelled");
            //拖拽的时候的区域可能是超出了拖拽区域
            if (!self.touchIndexPath) {
                return;
            }
            if(self.delegate && [self.delegate respondsToSelector:@selector(tableView:newCanMoveRowAtIndexPath:)]) {
                _canDrag = [self.delegate tableView:self newCanMoveRowAtIndexPath:self.selectedIndexPath];
            }
            if (!_canDrag) {
                return;
            }
            UITableViewCell *cell = [self cellForRowAtIndexPath:self.selectedIndexPath];
            if (self.delegate &&[self.delegate respondsToSelector:@selector(tableView:endMoveCellAtIndexPath:processCell:)]) {
                [self.delegate tableView:self endMoveCellAtIndexPath:self.selectedIndexPath processCell:cell];
            }
            [UIView animateWithDuration:0.2 animations:^{
                self.dragView.center = cell.center;
                self.dragView.transform = CGAffineTransformIdentity;
                self.dragView.alpha = 0.01;
            } completion:^(BOOL finished) {
                cell.hidden = NO;
                [self.dragView removeFromSuperview];
                if (self.delegate &&[self.delegate respondsToSelector:@selector(tableView:animationendMoveCellAtIndexPath:processCell:)]) {
                    [self.delegate tableView:self animationendMoveCellAtIndexPath:self.selectedIndexPath processCell:cell];
                }
                [self stopAutoScrollTimer];
            }];
        }
            break;
        default:
            break;
    }
}

/**
 截图
 */
- (UIView *)snapshotViewWithInputView:(UIView *)inputView {
    UIGraphicsBeginImageContextWithOptions(inputView.bounds.size, NO, 0);
    [inputView.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    UIView *snapshot = [[UIImageView alloc] initWithImage:image];
    return snapshot;
}

//更新数据源
- (void)updateDataWithIndexPath:(NSIndexPath *)moveIndexPath {
    if (self.dataSource && [self.dataSource respondsToSelector:@selector(tableView:newMoveRowAtIndexPath:toIndexPath:)]) {
        [self.dataSource tableView:self newMoveRowAtIndexPath:self.selectedIndexPath toIndexPath:moveIndexPath];
    }
}

/**
 *  检查截图是否到达边缘，并作出响应
 */
- (BOOL)checkIfSnapshotMeetsEdge{
    CGFloat minY = CGRectGetMinY(self.dragView.frame);
    CGFloat maxY = CGRectGetMaxY(self.dragView.frame);
//    NSLog(@"minY %f",minY);
//    NSLog(@"self.contentOffset.y %f",self.contentOffset.y);
    CGFloat h = 0;
    if ([self.delegate respondsToSelector:@selector(amendmentHeight)]) {
        h = [self.delegate amendmentHeight];
    }
    if (minY < self.contentOffset.y + h) {
        self.autoScrollDirection = SnapshotMeetsEdgeTop;
        return YES;
    }
    if (maxY > self.bounds.size.height + self.contentOffset.y) {
        self.autoScrollDirection = SnapshotMeetsEdgeBottom;
        return YES;
    }
    return NO;
}

/**
 *  创建定时器并运行
 */
- (void)startAutoScrollTimer{
    if (self.autoScrollTimer == nil) {
        self.autoScrollTimer = [CADisplayLink displayLinkWithTarget:self selector:@selector(startAutoScroll)];
        [self.autoScrollTimer addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

/**
 *  停止定时器并销毁
 */
- (void)stopAutoScrollTimer{
    if (self.autoScrollTimer) {
        [self.autoScrollTimer invalidate];
        self.autoScrollTimer = nil;
    }
}

/**
 *  开始自动滚动
 */
- (void)startAutoScroll{
    CGFloat pixelSpeed = 2;
    if (self.autoScrollDirection == SnapshotMeetsEdgeTop) {//向上滚动
        if (self.contentOffset.y > 0) {//向下滚动最大范围限制
            [self setContentOffset:CGPointMake(0, self.contentOffset.y - pixelSpeed)];
            self.dragView.center = CGPointMake(self.dragView.center.x, self.dragView.center.y - pixelSpeed);
//            return;
        }
    }else{//向下滚动
        if (self.contentOffset.y + self.bounds.size.height < self.contentSize.height) {//向下滚动最大范围限制
            [self setContentOffset:CGPointMake(0, self.contentOffset.y + pixelSpeed)];
            self.dragView.center = CGPointMake(self.dragView.center.x, self.dragView.center.y + pixelSpeed);
        }
    }
    /*
     交换cell
     */
    NSIndexPath *exchangePath= [self indexPathForRowAtPoint:self.dragView.center];
    if (exchangePath && self.selectedIndexPath != exchangePath ) {
        //判断下要移动的exchangeIndex 是否是在允许的范围内
        BOOL canExchange = YES;
        if (self.delegate && [self.delegate respondsToSelector:@selector(tableView:newTargetIndexPathForMoveFromRowAtIndexPath:toProposedIndexPath:)]) {
            canExchange = [self.delegate tableView:self newTargetIndexPathForMoveFromRowAtIndexPath:self.selectedIndexPath toProposedIndexPath:exchangePath];
        }
        if (!canExchange) {
            //正在拽的cell永远是隐藏的 解决复用的时候会重新出现的bug
            UITableViewCell *cell = [self cellForRowAtIndexPath:self.selectedIndexPath];
            cell.hidden = YES;
            return;
        }
        [self updateDataWithIndexPath:exchangePath];
        [self moveRowAtIndexPath:self.selectedIndexPath toIndexPath:exchangePath];
        self.selectedIndexPath = exchangePath;
    }
}

@end
