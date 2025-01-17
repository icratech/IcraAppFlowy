import 'dart:async';
import 'package:appflowy/core/notification/folder_notification.dart';
import 'package:appflowy/core/notification/user_notification.dart';
import 'package:dartz/dartz.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'dart:typed_data';
import 'package:flowy_infra/notifier.dart';
import 'package:appflowy_backend/protobuf/flowy-notification/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/notification.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/notification.pb.dart'
    as user;
import 'package:appflowy_backend/rust_stream.dart';

typedef UserProfileNotifyValue = Either<UserProfilePB, FlowyError>;
typedef AuthNotifyValue = Either<Unit, FlowyError>;

class UserListener {
  UserListener({
    required UserProfilePB userProfile,
  }) : _userProfile = userProfile;

  final UserProfilePB _userProfile;

  UserNotificationParser? _userParser;
  StreamSubscription<SubscribeObject>? _subscription;
  PublishNotifier<UserProfileNotifyValue>? _profileNotifier = PublishNotifier();

  void start({
    void Function(UserProfileNotifyValue)? onProfileUpdated,
  }) {
    if (onProfileUpdated != null) {
      _profileNotifier?.addPublishListener(onProfileUpdated);
    }

    _userParser = UserNotificationParser(
      id: _userProfile.id.toString(),
      callback: _userNotificationCallback,
    );
    _subscription = RustStreamReceiver.listen((observable) {
      _userParser?.parse(observable);
    });
  }

  Future<void> stop() async {
    _userParser = null;
    await _subscription?.cancel();
    _profileNotifier?.dispose();
    _profileNotifier = null;
  }

  void _userNotificationCallback(
    user.UserNotification ty,
    Either<Uint8List, FlowyError> result,
  ) {
    switch (ty) {
      case user.UserNotification.DidUpdateUserProfile:
        result.fold(
          (payload) =>
              _profileNotifier?.value = left(UserProfilePB.fromBuffer(payload)),
          (error) => _profileNotifier?.value = right(error),
        );
        break;
      default:
        break;
    }
  }
}

typedef WorkspaceSettingNotifyValue = Either<WorkspaceSettingPB, FlowyError>;

class UserWorkspaceListener {
  UserWorkspaceListener();

  PublishNotifier<WorkspaceSettingNotifyValue>? _settingChangedNotifier =
      PublishNotifier();

  FolderNotificationListener? _listener;

  void start({
    void Function(WorkspaceSettingNotifyValue)? onSettingUpdated,
  }) {
    if (onSettingUpdated != null) {
      _settingChangedNotifier?.addPublishListener(onSettingUpdated);
    }

    // The "current-workspace" is predefined in the backend. Do not try to
    // modify it
    _listener = FolderNotificationListener(
      objectId: "current-workspace",
      handler: _handleObservableType,
    );
  }

  void _handleObservableType(
    FolderNotification ty,
    Either<Uint8List, FlowyError> result,
  ) {
    switch (ty) {
      case FolderNotification.DidUpdateWorkspaceSetting:
        result.fold(
          (payload) => _settingChangedNotifier?.value =
              left(WorkspaceSettingPB.fromBuffer(payload)),
          (error) => _settingChangedNotifier?.value = right(error),
        );
        break;
      default:
        break;
    }
  }

  Future<void> stop() async {
    await _listener?.stop();

    _settingChangedNotifier?.dispose();
    _settingChangedNotifier = null;
  }
}
