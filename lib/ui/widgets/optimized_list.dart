// lib/ui/widgets/optimized_list.dart
// 성능 최적화된 리스트 위젯들
// const 생성자, 키 최적화, 불필요한 리빌드 방지

import 'package:flutter/material.dart';
import '../../design/tokens.dart';

/// 성능 최적화된 리스트뷰
///
/// 특징:
/// - 자동 키 관리
/// - const 생성자 활용
/// - 메모이제이션
/// - 지연 로딩 지원
class OptimizedListView<T> extends StatefulWidget {
  /// 리스트 데이터
  final List<T> items;

  /// 아이템 빌더
  final Widget Function(BuildContext context, T item, int index) itemBuilder;

  /// 키 추출기 (고유 식별자)
  final String Function(T item) keyExtractor;

  /// 구분자 빌더
  final Widget Function(BuildContext context, int index)? separatorBuilder;

  /// 스크롤 컨트롤러
  final ScrollController? controller;

  /// 패딩
  final EdgeInsetsGeometry? padding;

  /// 물리 속성
  final ScrollPhysics? physics;

  /// 스크롤 방향
  final Axis scrollDirection;

  /// 역순 여부
  final bool reverse;

  /// 수축 여부
  final bool shrinkWrap;

  /// 지연 로딩 임계값
  final int lazyLoadThreshold;

  /// 지연 로딩 콜백
  final VoidCallback? onLazyLoad;

  /// 새로고침 콜백
  final Future<void> Function()? onRefresh;

  /// 빈 상태 위젯
  final Widget? emptyWidget;

  /// 로딩 위젯
  final Widget? loadingWidget;

  /// 에러 위젯
  final Widget? errorWidget;

  /// 로딩 상태
  final bool isLoading;

  /// 에러 상태
  final bool hasError;

  const OptimizedListView({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.keyExtractor,
    this.separatorBuilder,
    this.controller,
    this.padding,
    this.physics,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.shrinkWrap = false,
    this.lazyLoadThreshold = 3,
    this.onLazyLoad,
    this.onRefresh,
    this.emptyWidget,
    this.loadingWidget,
    this.errorWidget,
    this.isLoading = false,
    this.hasError = false,
  });

  @override
  State<OptimizedListView<T>> createState() => _OptimizedListViewState<T>();
}

class _OptimizedListViewState<T> extends State<OptimizedListView<T>> {
  late ScrollController _scrollController;
  bool _isLazyLoading = false;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.controller ?? ScrollController();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _scrollController.dispose();
    } else {
      _scrollController.removeListener(_handleScroll);
    }
    super.dispose();
  }

  void _handleScroll() {
    if (_isLazyLoading || widget.onLazyLoad == null) return;

    final position = _scrollController.position;
    final threshold =
        position.maxScrollExtent - (position.viewportDimension * 0.8);

    if (position.pixels >= threshold) {
      _isLazyLoading = true;
      widget.onLazyLoad!();

      // 지연 로딩 쿨다운
      Future.delayed(const Duration(milliseconds: 500), () {
        _isLazyLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 에러 상태
    if (widget.hasError) {
      return widget.errorWidget ?? _buildDefaultErrorWidget();
    }

    // 로딩 상태 (초기 로딩)
    if (widget.isLoading && widget.items.isEmpty) {
      return widget.loadingWidget ?? _buildDefaultLoadingWidget();
    }

    // 빈 상태
    if (widget.items.isEmpty) {
      return widget.emptyWidget ?? _buildDefaultEmptyWidget();
    }

    // 리스트 빌드
    Widget listView =
        widget.separatorBuilder != null
            ? _buildSeparatedListView()
            : _buildRegularListView();

    // 새로고침 지원
    if (widget.onRefresh != null) {
      listView = RefreshIndicator(
        onRefresh: widget.onRefresh!,
        child: listView,
      );
    }

    return listView;
  }

  Widget _buildRegularListView() {
    return ListView.builder(
      key: ValueKey('list_${widget.items.length}'),
      controller: _scrollController,
      padding: widget.padding,
      physics: widget.physics,
      scrollDirection: widget.scrollDirection,
      reverse: widget.reverse,
      shrinkWrap: widget.shrinkWrap,
      itemCount: widget.items.length + (widget.isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        // 로딩 인디케이터 (추가 로딩)
        if (index >= widget.items.length) {
          return _buildLoadingIndicator();
        }

        final item = widget.items[index];
        final key = widget.keyExtractor(item);

        return _OptimizedListItem<T>(
          key: ValueKey(key),
          item: item,
          index: index,
          builder: widget.itemBuilder,
        );
      },
    );
  }

  Widget _buildSeparatedListView() {
    return ListView.separated(
      key: ValueKey('separated_list_${widget.items.length}'),
      controller: _scrollController,
      padding: widget.padding,
      physics: widget.physics,
      scrollDirection: widget.scrollDirection,
      reverse: widget.reverse,
      shrinkWrap: widget.shrinkWrap,
      itemCount: widget.items.length,
      itemBuilder: (context, index) {
        final item = widget.items[index];
        final key = widget.keyExtractor(item);

        return _OptimizedListItem<T>(
          key: ValueKey(key),
          item: item,
          index: index,
          builder: widget.itemBuilder,
        );
      },
      separatorBuilder: widget.separatorBuilder!,
    );
  }

  Widget _buildDefaultLoadingWidget() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildDefaultErrorWidget() {
    return const Center(child: Text('오류가 발생했습니다'));
  }

  Widget _buildDefaultEmptyWidget() {
    return const Center(child: Text('데이터가 없습니다'));
  }

  Widget _buildLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.all(DesignTokens.s16),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

/// 최적화된 리스트 아이템
class _OptimizedListItem<T> extends StatelessWidget {
  final T item;
  final int index;
  final Widget Function(BuildContext context, T item, int index) builder;

  const _OptimizedListItem({
    super.key,
    required this.item,
    required this.index,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return builder(context, item, index);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _OptimizedListItem<T> &&
        other.item == item &&
        other.index == index;
  }

  @override
  int get hashCode => Object.hash(item, index);
}

/// 성능 최적화된 그리드뷰
class OptimizedGridView<T> extends StatefulWidget {
  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final String Function(T item) keyExtractor;
  final int crossAxisCount;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double childAspectRatio;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final bool shrinkWrap;

  const OptimizedGridView({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.keyExtractor,
    this.crossAxisCount = 2,
    this.crossAxisSpacing = 8.0,
    this.mainAxisSpacing = 8.0,
    this.childAspectRatio = 1.0,
    this.padding,
    this.controller,
    this.physics,
    this.shrinkWrap = false,
  });

  @override
  State<OptimizedGridView<T>> createState() => _OptimizedGridViewState<T>();
}

class _OptimizedGridViewState<T> extends State<OptimizedGridView<T>> {
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      key: ValueKey('grid_${widget.items.length}'),
      controller: widget.controller,
      padding: widget.padding,
      physics: widget.physics,
      shrinkWrap: widget.shrinkWrap,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.crossAxisCount,
        crossAxisSpacing: widget.crossAxisSpacing,
        mainAxisSpacing: widget.mainAxisSpacing,
        childAspectRatio: widget.childAspectRatio,
      ),
      itemCount: widget.items.length,
      itemBuilder: (context, index) {
        final item = widget.items[index];
        final key = widget.keyExtractor(item);

        return _OptimizedListItem<T>(
          key: ValueKey(key),
          item: item,
          index: index,
          builder: widget.itemBuilder,
        );
      },
    );
  }
}

/// 메모이제이션된 위젯
class MemoizedWidget extends StatelessWidget {
  final Widget child;
  final List<Object?> dependencies;

  const MemoizedWidget({
    super.key,
    required this.child,
    required this.dependencies,
  });

  @override
  Widget build(BuildContext context) {
    return child;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MemoizedWidget &&
        _listEquals(other.dependencies, dependencies);
  }

  @override
  int get hashCode => Object.hashAll(dependencies);

  static bool _listEquals<E>(List<E> list1, List<E> list2) {
    if (identical(list1, list2)) return true;
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) return false;
    }
    return true;
  }
}

/// 성능 최적화된 슬라이버 리스트
class OptimizedSliverList<T> extends StatelessWidget {
  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final String Function(T item) keyExtractor;

  const OptimizedSliverList({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.keyExtractor,
  });

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final item = items[index];
          final key = keyExtractor(item);

          return _OptimizedListItem<T>(
            key: ValueKey(key),
            item: item,
            index: index,
            builder: itemBuilder,
          );
        },
        childCount: items.length,
        findChildIndexCallback: (key) {
          if (key is ValueKey<String>) {
            for (int i = 0; i < items.length; i++) {
              if (keyExtractor(items[i]) == key.value) {
                return i;
              }
            }
          }
          return null;
        },
      ),
    );
  }
}

/// 가상화된 리스트 (대량 데이터용)
class VirtualizedListView<T> extends StatefulWidget {
  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final String Function(T item) keyExtractor;
  final double itemExtent;
  final ScrollController? controller;
  final EdgeInsetsGeometry? padding;

  const VirtualizedListView({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.keyExtractor,
    required this.itemExtent,
    this.controller,
    this.padding,
  });

  @override
  State<VirtualizedListView<T>> createState() => _VirtualizedListViewState<T>();
}

class _VirtualizedListViewState<T> extends State<VirtualizedListView<T>> {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: ValueKey('virtualized_${widget.items.length}'),
      controller: widget.controller,
      padding: widget.padding,
      itemExtent: widget.itemExtent, // 고정 높이로 성능 최적화
      itemCount: widget.items.length,
      itemBuilder: (context, index) {
        final item = widget.items[index];
        final key = widget.keyExtractor(item);

        return _OptimizedListItem<T>(
          key: ValueKey(key),
          item: item,
          index: index,
          builder: widget.itemBuilder,
        );
      },
    );
  }
}

/// 성능 모니터링 위젯
class PerformanceMonitor extends StatefulWidget {
  final Widget child;
  final String name;
  final ValueChanged<Duration>? onRenderTime;

  const PerformanceMonitor({
    super.key,
    required this.child,
    required this.name,
    this.onRenderTime,
  });

  @override
  State<PerformanceMonitor> createState() => _PerformanceMonitorState();
}

class _PerformanceMonitorState extends State<PerformanceMonitor> {
  late Stopwatch _stopwatch;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _stopwatch.stop();
      final renderTime = _stopwatch.elapsed;
      widget.onRenderTime?.call(renderTime);

      // 개발 모드에서만 로그 출력
      assert(() {
        if (renderTime.inMilliseconds > 16) {
          // 60fps 기준
          debugPrint(
            'Performance Warning: ${widget.name} took ${renderTime.inMilliseconds}ms to render',
          );
        }
        return true;
      }());
    });

    return widget.child;
  }
}
