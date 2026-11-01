package com.fangshi.android.fs_music

import android.media.MediaMetadataRetriever
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        //扫描时探测音频时长（MediaMetadataRetriever 原生读元数据）：
        //不占用播放器实例（just_audio_background 全局只允许一个播放器）
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fs_music/metadata")
            .setMethodCallHandler { call, result ->
                if (call.method == "getDuration") {
                    val path = call.argument<String>("path")
                    val retriever = MediaMetadataRetriever()
                    try {
                        retriever.setDataSource(path)
                        val ms = retriever.extractMetadata(
                            MediaMetadataRetriever.METADATA_KEY_DURATION
                        )
                        result.success(ms?.toLongOrNull() ?: 0L)
                    } catch (e: Exception) {
                        //读取失败：返回 0，由 Dart 侧兜底
                        result.success(0L)
                    } finally {
                        retriever.release()
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
