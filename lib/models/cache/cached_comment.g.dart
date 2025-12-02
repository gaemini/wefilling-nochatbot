// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cached_comment.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CachedCommentAdapter extends TypeAdapter<CachedComment> {
  @override
  final int typeId = 1;

  @override
  CachedComment read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CachedComment(
      id: fields[0] as String,
      data: (fields[1] as Map).cast<String, dynamic>(),
      cachedAt: fields[2] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, CachedComment obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.data)
      ..writeByte(2)
      ..write(obj.cachedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CachedCommentAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
