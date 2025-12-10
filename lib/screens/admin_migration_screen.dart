// lib/screens/admin_migration_screen.dart
// 데이터 마이그레이션 관리자 화면

import 'package:flutter/material.dart';
import '../services/data_migration_service.dart';
import '../utils/logger.dart';

class AdminMigrationScreen extends StatefulWidget {
  const AdminMigrationScreen({Key? key}) : super(key: key);

  @override
  State<AdminMigrationScreen> createState() => _AdminMigrationScreenState();
}

class _AdminMigrationScreenState extends State<AdminMigrationScreen> {
  final DataMigrationService _migrationService = DataMigrationService();
  bool _isLoading = false;
  String _statusMessage = '';
  Map<String, dynamic>? _migrationStatus;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '마이그레이션 상태 확인 중...';
    });

    try {
      final status = await _migrationService.checkMigrationStatus();
      setState(() {
        _migrationStatus = status;
        _statusMessage = '상태 확인 완료';
      });
    } catch (e) {
      setState(() {
        _statusMessage = '상태 확인 실패: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _runMigration() async {
    // 확인 다이얼로그
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ 데이터 마이그레이션'),
        content: const Text(
          '모든 모임 데이터에 viewCount와 commentCount 필드를 추가합니다.\n\n'
          '이 작업은 되돌릴 수 없습니다. 계속하시겠습니까?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('실행'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _statusMessage = '마이그레이션 실행 중... (시간이 걸릴 수 있습니다)';
    });

    try {
      final success = await _migrationService.migrateMeetupStatistics();
      
      setState(() {
        _statusMessage = success 
            ? '✅ 마이그레이션 완료!' 
            : '❌ 마이그레이션 실패';
      });

      if (success) {
        // 상태 다시 확인
        await _checkStatus();
        
        // 성공 메시지
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('마이그레이션이 성공적으로 완료되었습니다!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _statusMessage = '❌ 마이그레이션 실패: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('데이터 마이그레이션'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 경고 메시지
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                border: Border.all(color: Colors.orange),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '⚠️ 관리자 전용 기능입니다.\n'
                      '이 기능은 데이터베이스를 직접 수정합니다.',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 상태 정보
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '마이그레이션 상태',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    if (_migrationStatus != null) ...[
                      _buildStatusRow('샘플 모임 수', '${_migrationStatus!['totalSampled']}개'),
                      _buildStatusRow('viewCount 필드', '${_migrationStatus!['withViewCount']}개 (${_migrationStatus!['viewCountPercentage']}%)'),
                      _buildStatusRow('commentCount 필드', '${_migrationStatus!['withCommentCount']}개 (${_migrationStatus!['commentCountPercentage']}%)'),
                      _buildStatusRow('마이그레이션 필요', _migrationStatus!['needsMigration'] ? '예' : '아니오'),
                    ],
                    
                    const SizedBox(height: 12),
                    Text(
                      _statusMessage,
                      style: TextStyle(
                        color: _statusMessage.contains('✅') 
                            ? Colors.green 
                            : _statusMessage.contains('❌')
                                ? Colors.red
                                : Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 액션 버튼들
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _checkStatus,
                    icon: const Icon(Icons.refresh),
                    label: const Text('상태 새로고침'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading || 
                        (_migrationStatus?['needsMigration'] != true) 
                        ? null : _runMigration,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('마이그레이션 실행'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 로딩 인디케이터
            if (_isLoading)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('처리 중...'),
                  ],
                ),
              ),

            const Spacer(),

            // 설명
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '마이그레이션 내용:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text('• 모든 모임에 viewCount: 0 필드 추가'),
                  Text('• 모든 모임에 commentCount 필드 추가 (실제 댓글 수 계산)'),
                  Text('• updatedAt 타임스탬프 업데이트'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}







