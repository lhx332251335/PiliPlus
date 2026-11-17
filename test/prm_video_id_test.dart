import 'package:PiliPlus/common/widgets/video_card/video_card_v.dart';
import 'package:PiliPlus/models/dynamics/result.dart' as dynamics;
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/models_new/fav/fav_detail/media.dart';
import 'package:PiliPlus/models_new/space/space_archive/item.dart';
import 'package:PiliPlus/pages/dynamics/widgets/video_panel.dart';
import 'package:PiliPlus/pages/fav_detail/widget/fav_video_card.dart';
import 'package:PiliPlus/pages/member_home/widgets/video_card_v_member_home.dart';
import 'package:PiliPlus/prm/overlay.dart';
import 'package:PiliPlus/prm/video_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// Inspect the actual card build and cover LayoutBuilder without mounting image,
// service or player descendants. This catches missing/wrong production wiring,
// without requiring app storage, network or native media initialization.
PrmProgressOverlay? _coverOverlay(Widget widget, BuildContext context) {
  if (widget is PrmProgressOverlay) return widget;
  if (widget is LayoutBuilder) {
    return _coverOverlay(
      widget.builder(
        context,
        const BoxConstraints.tightFor(width: 160, height: 90),
      ),
      context,
    );
  }
  final children = switch (widget) {
    Card(:final child) ||
    Material(:final child) ||
    InkWell(:final child) => [?child],
    MultiChildRenderObjectWidget(:final children) => children,
    SingleChildRenderObjectWidget(:final child) => [?child],
    _ => <Widget>[],
  };
  for (final child in children) {
    final overlay = _coverOverlay(child, context);
    if (overlay != null) return overlay;
  }
  return null;
}

void main() {
  const bvid = 'BV1xx411c7mD';

  test('AV cards preserve a supported BVID exactly', () {
    expect(PrmVideoId.recommendation(goto: 'av', bvid: bvid), bvid);
    expect(PrmVideoId.dynamicCard(type: 'DYNAMIC_TYPE_AV', bvid: bvid), bvid);
    expect(
      PrmVideoId.dynamicCard(type: 'DYNAMIC_TYPE_UGC_SEASON', bvid: bvid),
      bvid,
    );
    expect(PrmVideoId.favorite(type: 2, bvid: bvid), bvid);
    expect(PrmVideoId.memberHome(goto: 'av', bvid: bvid), bvid);
  });

  test(
    'BVIDs are not trimmed, recased, repaired or replaced by episode IDs',
    () {
      for (final invalid in <String?>[
        null,
        '',
        ' $bvid',
        '$bvid ',
        '$bvid\n',
        'bv1xx411c7mD',
        'BV1xx411c7m',
        'BV1xx411c7mDD',
        'BV1xx411c7m_',
        'ep123',
        '123',
      ]) {
        expect(
          PrmVideoId.recommendation(goto: 'av', bvid: invalid, episodeId: 123),
          isNull,
        );
        expect(
          PrmVideoId.dynamicCard(
            type: 'DYNAMIC_TYPE_AV',
            bvid: invalid,
            episodeId: 123,
          ),
          isNull,
        );
        expect(
          PrmVideoId.favorite(type: 2, bvid: invalid, episodeId: 123),
          isNull,
        );
        expect(
          PrmVideoId.memberHome(goto: 'av', bvid: invalid, episodeId: '123'),
          isNull,
        );
      }
    },
  );

  test('bangumi, PGC, PGC_UNION and type 24 map episode IDs, not BVIDs', () {
    expect(
      PrmVideoId.recommendation(goto: 'bangumi', bvid: bvid, episodeId: 123),
      'ep123',
    );
    for (final type in ['DYNAMIC_TYPE_PGC', 'DYNAMIC_TYPE_PGC_UNION']) {
      expect(
        PrmVideoId.dynamicCard(type: type, bvid: bvid, episodeId: 123),
        'ep123',
      );
    }
    expect(PrmVideoId.favorite(type: 24, bvid: bvid, episodeId: 123), 'ep123');
    expect(
      PrmVideoId.memberHome(goto: 'bangumi', bvid: bvid, episodeId: '123'),
      'ep123',
    );
    // A digit string is kept exact; it is never parsed/reformatted.
    expect(
      PrmVideoId.memberHome(goto: 'bangumi', episodeId: '00123'),
      'ep00123',
    );
  });

  test(
    'invalid or missing episode IDs fail closed, even with a valid BVID',
    () {
      for (final invalid in <Object?>[
        null,
        '',
        0,
        -1,
        1.0,
        1.5,
        true,
        '0',
        '000',
        '-1',
        '+1',
        ' 123',
        '123 ',
        '123\n',
        '1.0',
        '1e3',
        'ep123',
        'ss123',
        '１２３',
        '123/4',
        List.filled(79, '1').join(),
      ]) {
        expect(
          PrmVideoId.recommendation(
            goto: 'bangumi',
            bvid: bvid,
            episodeId: invalid,
          ),
          isNull,
          reason: '$invalid',
        );
        for (final type in ['DYNAMIC_TYPE_PGC', 'DYNAMIC_TYPE_PGC_UNION']) {
          expect(
            PrmVideoId.dynamicCard(type: type, bvid: bvid, episodeId: invalid),
            isNull,
            reason: '$type: $invalid',
          );
        }
        expect(
          PrmVideoId.favorite(type: 24, bvid: bvid, episodeId: invalid),
          isNull,
        );
        expect(
          PrmVideoId.memberHome(
            goto: 'bangumi',
            bvid: bvid,
            episodeId: invalid,
          ),
          isNull,
        );
      }
    },
  );

  test('unsupported cards and ambiguous member PGC AV IDs do not match', () {
    for (final goto in <String?>[null, '', 'picture', 'live']) {
      expect(
        PrmVideoId.recommendation(goto: goto, bvid: bvid, episodeId: 123),
        isNull,
      );
      expect(
        PrmVideoId.memberHome(goto: goto, bvid: bvid, episodeId: '123'),
        isNull,
      );
    }
    for (final type in <String?>[null, '', 'DYNAMIC_TYPE_COURSES_SEASON']) {
      expect(
        PrmVideoId.dynamicCard(type: type, bvid: bvid, episodeId: 123),
        isNull,
      );
    }
    for (final type in <int?>[null, 0, 12]) {
      expect(
        PrmVideoId.favorite(type: type, bvid: bvid, episodeId: 123),
        isNull,
      );
    }
    // On these member cards param is an AV ID, not an episode ID.
    expect(
      PrmVideoId.memberHome(
        goto: 'av',
        isPgc: true,
        bvid: bvid,
        episodeId: '123',
      ),
      isNull,
    );
    expect(
      PrmVideoId.memberHome(goto: 'bangumi', isPgc: true, episodeId: '123'),
      'ep123',
    );
  });

  testWidgets('production card covers receive the exact mapped PRM identity', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    void expectCover(Widget built, String? expected) {
      final overlay = _coverOverlay(built, context);
      expect(
        overlay,
        isNotNull,
        reason: 'production cover must use PRM overlay',
      );
      expect(overlay!.videoId, expected);
    }

    for (final goto in ['av', 'bangumi', 'picture']) {
      final item = RcmdVideoItemModel.fromJson({
        'goto': goto,
        'title': 'fixture',
        'duration': 0,
        'bvid': bvid,
        'owner': <String, dynamic>{},
        'stat': <String, dynamic>{},
      })..param = 123;
      expectCover(VideoCardV(videoItem: item).build(context), switch (goto) {
        'av' => bvid,
        'bangumi' => 'ep123',
        _ => null,
      });
      item
        ..param = -1
        ..bvid = ' $bvid';
      expectCover(VideoCardV(videoItem: item).build(context), null);
    }

    for (final type in [
      'DYNAMIC_TYPE_AV',
      'DYNAMIC_TYPE_UGC_SEASON',
      'DYNAMIC_TYPE_PGC',
      'DYNAMIC_TYPE_PGC_UNION',
      'DYNAMIC_TYPE_COURSES_SEASON',
    ]) {
      final video = dynamics.DynamicArchiveModel(
        bvid: bvid,
        epid: 123,
        cover: '',
      );
      final item = dynamics.DynamicItemModel.fromJson({'type': type});
      item.modules.moduleDynamic = dynamics.ModuleDynamicModel(
        major: dynamics.DynamicMajorModel(
          archive: video,
          ugcSeason: video,
          pgc: video,
          courses: video,
        ),
      );
      Widget build() => videoSeasonWidget(
        context,
        floor: 1,
        theme: Theme.of(context),
        item: item,
        isSave: false,
        isDetail: false,
      );
      expectCover(build(), switch (type) {
        'DYNAMIC_TYPE_AV' || 'DYNAMIC_TYPE_UGC_SEASON' => bvid,
        'DYNAMIC_TYPE_PGC' || 'DYNAMIC_TYPE_PGC_UNION' => 'ep123',
        _ => null,
      });
      video
        ..epid = null
        ..bvid = 'ep123';
      expectCover(build(), null);
    }

    for (final type in [2, 24, 12]) {
      final item = FavDetailItemModel(
        type: type,
        id: 123,
        bvid: bvid,
        title: 'fixture',
      );
      expectCover(FavVideoCardH(item: item).build(context), switch (type) {
        2 => bvid,
        24 => 'ep123',
        _ => null,
      });
      item
        ..id = 0
        ..bvid = '$bvid\n';
      expectCover(FavVideoCardH(item: item).build(context), null);
    }

    for (final goto in ['av', 'bangumi', 'picture']) {
      final item = SpaceArchiveItem.fromJson({
        'goto': goto,
        'title': 'fixture',
        'duration': 0,
        'bvid': bvid,
        'param': '123',
        'is_cooperation': true,
      });
      final card = VideoCardVMemberHome(item);
      final built = card.build(context);
      expectCover(built, switch (goto) {
        'av' => bvid,
        'bangumi' => 'ep123',
        _ => null,
      });
      expect(_coverOverlay(built, context)!.topRightBadge, '合作');
      item
        ..param = '123 '
        ..bvid = 'bv1xx411c7mD';
      expectCover(card.build(context), null);
      item
        ..isPgc = true
        ..param = '123'
        ..bvid = bvid;
      expectCover(card.build(context), goto == 'bangumi' ? 'ep123' : null);
    }
    expect(tester.takeException(), isNull);
  });
}
