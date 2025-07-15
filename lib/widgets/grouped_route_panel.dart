import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/route_manager.dart';
import '../models/route_info.dart';
import '../controllers/synology_controller.dart';

class GroupedRoutePanel extends StatefulWidget {
  final RouteManager routeManager;
  final int selectedVehicleId;
  final Function(int) onVehicleSelected;
  final VoidCallback onRouteUpdated;

  const GroupedRoutePanel({
    super.key,
    required this.routeManager,
    required this.selectedVehicleId,
    required this.onVehicleSelected,
    required this.onRouteUpdated,
  });

  @override
  State<GroupedRoutePanel> createState() => _GroupedRoutePanelState();
}

class _GroupedRoutePanelState extends State<GroupedRoutePanel> {
  bool _hasUnsavedChanges = false;
  bool _isSaving = false;

  // 변경사항 표시
  void _markAsChanged() {
    if (!_hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = true;
      });
    }
  }

  // 저장 완료 처리
  void _markAsSaved() {
    setState(() {
      _hasUnsavedChanges = false;
    });
  }

  // 경로 데이터 저장
  Future<void> _saveRouteData() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final synologyController = Get.find<SynologyController>();

      if (!synologyController.isConnected.value) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('NAS 연결이 필요합니다. 설정에서 먼저 연결해주세요.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // 저장 진행
      final success = await synologyController.saveRouteData(widget.routeManager);

      if (success) {
        _markAsSaved();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('경로 그룹 정보가 성공적으로 저장되었습니다'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('경로 그룹 정보 저장 중 오류가 발생했습니다'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('저장 오류: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupNames = widget.routeManager.allGroupNames;

    // 그룹이 없는 경우 기본 그룹 생성
    if (groupNames.isEmpty) {
      widget.routeManager.createGroup(RouteManager.defaultGroupName);
    }

    return Column(
      children: [
        // 그룹 관리 헤더
        _buildGroupManagementHeader(),

        // 저장 상태 및 버튼
        _buildSaveSection(),

        const SizedBox(height: 8),

        // 그룹별 경로 리스트
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: groupNames.map((groupName) => _buildGroupExpansionTile(groupName)).toList(),
            ),
          ),
        ),
      ],
    );
  }

  // 저장 상태 및 버튼 섹션
  Widget _buildSaveSection() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _hasUnsavedChanges ? Colors.orange.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _hasUnsavedChanges ? Colors.orange.shade200 : Colors.green.shade200,
        ),
      ),
      child: Row(
        children: [
          // 저장 상태 아이콘 및 텍스트
          Icon(
            _hasUnsavedChanges ? Icons.warning : Icons.check_circle,
            color: _hasUnsavedChanges ? Colors.orange.shade700 : Colors.green.shade700,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _hasUnsavedChanges ? '저장되지 않은 변경사항이 있습니다' : '모든 변경사항이 저장되었습니다',
              style: TextStyle(
                fontSize: 12,
                color: _hasUnsavedChanges ? Colors.orange.shade800 : Colors.green.shade800,
                fontWeight: _hasUnsavedChanges ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          // 저장 버튼
          ElevatedButton.icon(
            onPressed: _hasUnsavedChanges && !_isSaving ? _saveRouteData : null,
            icon: _isSaving
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _hasUnsavedChanges ? Colors.white : Colors.grey,
                      ),
                    ),
                  )
                : Icon(
                    Icons.save,
                    size: 16,
                    color: _hasUnsavedChanges ? Colors.white : Colors.grey,
                  ),
            label: Text(
              _isSaving ? '저장 중...' : '저장',
              style: const TextStyle(fontSize: 12),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _hasUnsavedChanges ? Colors.blue : Colors.grey.shade300,
              foregroundColor: _hasUnsavedChanges ? Colors.white : Colors.grey.shade600,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(80, 32),
            ),
          ),
        ],
      ),
    );
  }

  // 그룹 관리 헤더 위젯
  Widget _buildGroupManagementHeader() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.folder, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              Text(
                '경로 그룹 관리',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
              const Spacer(),
              // 새 그룹 추가 버튼
              IconButton(
                icon: const Icon(Icons.add, color: Colors.blue),
                tooltip: '새 그룹 추가',
                onPressed: _showAddGroupDialog,
              ),
            ],
          ),
          // 현재 활성 그룹 표시
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '활성 그룹: ${widget.routeManager.currentGroup}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 그룹별 ExpansionTile 생성
  Widget _buildGroupExpansionTile(String groupName) {
    final routes = widget.routeManager.getRoutesByGroup(groupName);
    final isCurrentGroup = widget.routeManager.currentGroup == groupName;
    final isDefaultGroup = groupName == RouteManager.defaultGroupName;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(
          color: isCurrentGroup ? Colors.blue.shade300 : Colors.grey.shade300,
          width: isCurrentGroup ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        title: Row(
          children: [
            Icon(
              Icons.directions_bus,
              color: isCurrentGroup ? Colors.blue : Colors.grey.shade600,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                groupName,
                style: TextStyle(
                  fontWeight: isCurrentGroup ? FontWeight.bold : FontWeight.normal,
                  color: isCurrentGroup ? Colors.blue.shade700 : Colors.black87,
                ),
              ),
            ),
            // 경로 개수 뱃지
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isCurrentGroup ? Colors.blue : Colors.grey,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${routes.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: isCurrentGroup
            ? Text(
                '현재 활성 그룹',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.blue.shade600,
                  fontStyle: FontStyle.italic,
                ),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 그룹 활성화 버튼
            if (!isCurrentGroup)
              IconButton(
                icon: const Icon(Icons.radio_button_unchecked, size: 20),
                tooltip: '이 그룹을 활성화',
                onPressed: () {
                  setState(() {
                    widget.routeManager.setCurrentGroup(groupName);
                  });
                  widget.onRouteUpdated();
                },
              ),
            if (isCurrentGroup) const Icon(Icons.radio_button_checked, color: Colors.blue, size: 20),

            // 그룹 메뉴 버튼
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              itemBuilder: (context) => [
                if (!isDefaultGroup) ...[
                  const PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 16),
                        SizedBox(width: 8),
                        Text('이름 변경'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 16, color: Colors.red),
                        SizedBox(width: 8),
                        Text('그룹 삭제', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
                const PopupMenuItem(
                  value: 'add_vehicle',
                  child: Row(
                    children: [
                      Icon(Icons.add, size: 16, color: Colors.green),
                      SizedBox(width: 8),
                      Text('차량 추가', style: TextStyle(color: Colors.green)),
                    ],
                  ),
                ),
              ],
              onSelected: (action) => _handleGroupAction(action, groupName),
            ),
          ],
        ),
        children: [
          if (routes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '이 그룹에는 아직 차량이 없습니다.',
                style: TextStyle(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            _buildReorderableVehicleList(routes, groupName),
        ],
      ),
    );
  }

  // 차량 리스트 타일 생성
  Widget _buildVehicleListTile(RouteInfo route, String groupName) {
    final isSelected = widget.selectedVehicleId == route.vehicleId && widget.routeManager.currentGroup == groupName;
    final pointCount = route.points.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        dense: true,
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.directions_bus,
            color: isSelected ? Colors.white : Colors.grey.shade600,
            size: 20,
          ),
        ),
        title: Text(
          route.vehicleName.isEmpty ? '${route.vehicleId + 1}호차' : route.vehicleName,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.blue.shade700 : Colors.black87,
          ),
        ),
        subtitle: Text(
          '$pointCount개 지점 • ${route.totalDistance.toStringAsFixed(1)}km • ${route.estimatedTime}분',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 활성 상태 표시
            if (route.isActive) Icon(Icons.check_circle, color: Colors.green.shade600, size: 16) else Icon(Icons.pause_circle, color: Colors.orange.shade600, size: 16),

            const SizedBox(width: 8),

            // 차량 메뉴
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 16),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'rename',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 16, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('이름 변경', style: TextStyle(color: Colors.blue)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'move',
                  child: Row(
                    children: [
                      Icon(Icons.move_to_inbox, size: 16),
                      SizedBox(width: 8),
                      Text('다른 그룹으로 이동'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'toggle_active',
                  child: Row(
                    children: [
                      Icon(
                        route.isActive ? Icons.pause : Icons.play_arrow,
                        size: 16,
                        color: route.isActive ? Colors.orange : Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        route.isActive ? '비활성화' : '활성화',
                        style: TextStyle(
                          color: route.isActive ? Colors.orange : Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 16, color: Colors.red),
                      SizedBox(width: 8),
                      Text('차량 삭제', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
              onSelected: (action) => _handleVehicleAction(action, route, groupName),
            ),
          ],
        ),
        onTap: () {
          // 그룹이 다르면 먼저 그룹을 활성화
          if (widget.routeManager.currentGroup != groupName) {
            widget.routeManager.setCurrentGroup(groupName);
          }

          // 차량 선택
          widget.onVehicleSelected(route.vehicleId);
          widget.onRouteUpdated();
        },
        selected: isSelected,
        selectedTileColor: Colors.blue.shade50,
      ),
    );
  }

  // 드래그 앤 드롭 가능한 차량 리스트 생성
  Widget _buildReorderableVehicleList(List<RouteInfo> routes, String groupName) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: routes.length,
      onReorder: (oldIndex, newIndex) {
        // newIndex가 oldIndex보다 큰 경우 조정
        if (newIndex > oldIndex) {
          newIndex--;
        }

        final success = widget.routeManager.reorderVehicleInGroup(groupName, oldIndex, newIndex);
        if (success) {
          setState(() {});
          _markAsChanged();
          widget.onRouteUpdated();
        }
      },
      itemBuilder: (context, index) {
        final route = routes[index];
        return _buildDraggableVehicleListTile(route, groupName, index);
      },
    );
  }

  // 드래그 가능한 차량 리스트 타일 생성
  Widget _buildDraggableVehicleListTile(RouteInfo route, String groupName, int index) {
    final isSelected = widget.selectedVehicleId == route.vehicleId && widget.routeManager.currentGroup == groupName;
    final pointCount = route.points.length;

    return Container(
      key: ValueKey('${groupName}_${route.vehicleId}_$index'),
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      child: Card(
        elevation: 1,
        child: ListTile(
          dense: true,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 4), // 왼쪽 여백
              // 드래그 핸들
              Icon(
                Icons.drag_handle,
                color: Colors.grey.shade400,
                size: 16,
              ),
              const SizedBox(width: 8), // 핸들과 아이콘 사이 여백 증가
              // 차량 아이콘
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.directions_bus,
                  color: isSelected ? Colors.white : Colors.grey.shade600,
                  size: 16,
                ),
              ),
              const SizedBox(width: 4), // 오른쪽 여백
            ],
          ),
          title: Text(
            route.vehicleName.isEmpty ? '${route.vehicleId + 1}호차' : route.vehicleName,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.blue.shade700 : Colors.black87,
            ),
          ),
          subtitle: Text(
            '$pointCount개 지점 • ${route.totalDistance.toStringAsFixed(1)}km • ${route.estimatedTime}분',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 활성화 상태 표시
              Icon(
                route.isActive ? Icons.visibility : Icons.visibility_off,
                color: route.isActive ? Colors.green : Colors.red,
                size: 16,
              ),
              const SizedBox(width: 4),
              // 차량 메뉴 버튼
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 16),
                        SizedBox(width: 8),
                        Text('이름 변경'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle_active',
                    child: Row(
                      children: [
                        Icon(
                          route.isActive ? Icons.visibility_off : Icons.visibility,
                          size: 16,
                          color: route.isActive ? Colors.orange : Colors.green,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          route.isActive ? '비활성화' : '활성화',
                          style: TextStyle(
                            color: route.isActive ? Colors.orange : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'move',
                    child: Row(
                      children: [
                        Icon(Icons.swap_horiz, size: 16, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('다른 그룹으로 이동', style: TextStyle(color: Colors.blue)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 16, color: Colors.red),
                        SizedBox(width: 8),
                        Text('차량 삭제', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
                onSelected: (action) => _handleVehicleAction(action, route, groupName),
              ),
            ],
          ),
          onTap: () {
            // 그룹이 다르면 먼저 그룹을 활성화
            if (widget.routeManager.currentGroup != groupName) {
              widget.routeManager.setCurrentGroup(groupName);
            }

            // 차량 선택
            widget.onVehicleSelected(route.vehicleId);
            widget.onRouteUpdated();
          },
          selected: isSelected,
          selectedTileColor: Colors.blue.shade50,
        ),
      ),
    );
  }

  // 그룹 액션 처리
  void _handleGroupAction(String action, String groupName) {
    switch (action) {
      case 'rename':
        _showRenameGroupDialog(groupName);
        break;
      case 'delete':
        _showDeleteGroupDialog(groupName);
        break;
      case 'add_vehicle':
        _showAddVehicleToGroupDialog(groupName);
        break;
    }
  }

  // 차량 액션 처리
  void _handleVehicleAction(String action, RouteInfo route, String groupName) {
    switch (action) {
      case 'rename':
        _showRenameVehicleDialog(route, groupName);
        break;
      case 'move':
        _showMoveVehicleDialog(route, groupName);
        break;
      case 'toggle_active':
        setState(() {
          route.isActive = !route.isActive;
        });
        _markAsChanged();
        widget.onRouteUpdated();
        break;
      case 'delete':
        _showDeleteVehicleDialog(route, groupName);
        break;
    }
  }

  // 새 그룹 추가 다이얼로그
  void _showAddGroupDialog() {
    final groupNameController = TextEditingController();

    // 그룹 추가 처리 함수
    void processGroupAdd() {
      final groupName = groupNameController.text.trim();
      if (groupName.isNotEmpty) {
        // 성공 메시지 먼저 표시
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('그룹 "$groupName"이(가) 추가되었습니다'),
            backgroundColor: Colors.green,
          ),
        );

        setState(() {
          widget.routeManager.createGroup(groupName);
        });
        _markAsChanged();
        Navigator.pop(context);
        widget.onRouteUpdated();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('그룹 이름을 입력해주세요'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('새 그룹 추가'),
        content: TextField(
          controller: groupNameController,
          decoration: const InputDecoration(
            labelText: '그룹 이름',
            hintText: '예: 오전노선, 오후노선',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: processGroupAdd,
            child: const Text('추가'),
          ),
        ],
      ),
    ).then((_) {
      groupNameController.dispose();
    });
  }

  // 그룹 이름 변경 다이얼로그
  void _showRenameGroupDialog(String oldName) {
    final groupNameController = TextEditingController(text: oldName);

    // 그룹 이름 변경 처리 함수
    void processGroupRename() {
      final newName = groupNameController.text.trim();
      if (newName.isNotEmpty && newName != oldName) {
        final success = widget.routeManager.renameGroup(oldName, newName);
        if (success) {
          // 성공 메시지 먼저 표시
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('그룹 이름이 "$newName"으로 변경되었습니다'),
              backgroundColor: Colors.green,
            ),
          );

          setState(() {});
          _markAsChanged();
          Navigator.pop(context);
          widget.onRouteUpdated();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('그룹 이름 변경에 실패했습니다. 이미 존재하는 이름일 수 있습니다.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        Navigator.pop(context);
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('그룹 이름 변경'),
        content: TextField(
          controller: groupNameController,
          decoration: const InputDecoration(
            labelText: '새 그룹 이름',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: processGroupRename,
            child: const Text('변경'),
          ),
        ],
      ),
    ).then((_) {
      groupNameController.dispose();
    });
  }

  // 그룹 삭제 다이얼로그
  void _showDeleteGroupDialog(String groupName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('그룹 삭제'),
        content: Text('정말로 "$groupName" 그룹을 삭제하시겠습니까?\n그룹 내의 모든 차량 경로가 함께 삭제됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              final success = widget.routeManager.deleteGroup(groupName);
              if (success) {
                setState(() {});
                _markAsChanged();
                Navigator.pop(context);
                widget.onRouteUpdated();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // 그룹에 차량 추가 다이얼로그
  void _showAddVehicleToGroupDialog(String groupName) {
    final nameController = TextEditingController();

    // 차량 추가 처리 함수
    void processVehicleAdd() {
      final vehicleName = nameController.text.trim();
      if (vehicleName.isNotEmpty) {
        // 성공 메시지 먼저 표시
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('차량 "$vehicleName"이(가) 추가되었습니다'),
            backgroundColor: Colors.green,
          ),
        );

        // 해당 그룹의 기존 차량 수 확인
        final routes = widget.routeManager.getRoutesByGroup(groupName);
        final nextVehicleId = routes.isNotEmpty ? routes.map((r) => r.vehicleId).reduce((a, b) => a > b ? a : b) + 1 : 0;

        // 새 차량을 해당 그룹에 추가
        widget.routeManager.addRoute(
          vehicleId: nextVehicleId,
          vehicleName: vehicleName,
          points: [],
          totalDistance: 0.0,
          estimatedTime: 0,
          groupName: groupName,
        );

        setState(() {});
        _markAsChanged();
        Navigator.pop(context);
        widget.onRouteUpdated();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('차량 이름을 입력해주세요'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$groupName에 차량 추가'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: '차량 이름',
            hintText: '예: 1호차, 아침셔틀',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (_) {
            // UI 충돌 방지를 위해 다음 프레임에서 처리
            Future.microtask(() => processVehicleAdd());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: processVehicleAdd,
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }

  // 차량 이름 변경 다이얼로그
  void _showRenameVehicleDialog(RouteInfo route, String groupName) {
    final nameController = TextEditingController(text: route.vehicleName);

    // 차량 이름 변경 처리 함수
    void processVehicleRename() {
      final newName = nameController.text.trim();
      if (newName.isNotEmpty && newName != route.vehicleName) {
        // 먼저 성공 메시지 표시
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('차량 이름이 "$newName"으로 변경되었습니다'),
            backgroundColor: Colors.green,
          ),
        );

        setState(() {
          route.vehicleName = newName;
        });
        _markAsChanged();
        Navigator.pop(context);
        widget.onRouteUpdated();
      } else if (newName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('차량 이름을 입력해주세요'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        Navigator.pop(context);
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('차량 이름 변경'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('현재 이름: ${route.vehicleName}'),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '새 차량 이름',
                hintText: '예: 1호차, 오전셔틀, 특별노선',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: processVehicleRename,
            child: const Text('변경'),
          ),
        ],
      ),
    ).then((_) {
      nameController.dispose();
    });
  }

  // 차량을 다른 그룹으로 이동 다이얼로그
  void _showMoveVehicleDialog(RouteInfo route, String currentGroup) {
    final otherGroups = widget.routeManager.allGroupNames.where((group) => group != currentGroup).toList();

    if (otherGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이동할 수 있는 다른 그룹이 없습니다.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${route.vehicleName} 이동'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('이동할 그룹을 선택하세요:'),
            const SizedBox(height: 16),
            ...otherGroups.map((groupName) => ListTile(
                  title: Text(groupName),
                  leading: const Icon(Icons.folder),
                  onTap: () {
                    final success = widget.routeManager.moveRouteToGroup(
                      route.vehicleId,
                      currentGroup,
                      groupName,
                    );
                    if (success) {
                      // 차량을 이동한 후 해당 그룹을 활성화
                      widget.routeManager.setCurrentGroup(groupName);
                      setState(() {});
                      _markAsChanged();
                      Navigator.pop(context);
                      widget.onRouteUpdated();
                    }
                  },
                )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
        ],
      ),
    );
  }

  // 차량 삭제 다이얼로그
  void _showDeleteVehicleDialog(RouteInfo route, String groupName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('차량 삭제'),
        content: Text('정말로 "${route.vehicleName}"을(를) 삭제하시겠습니까?\n모든 경로 정보가 함께 삭제됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              widget.routeManager.removeVehicle(route.vehicleId);
              setState(() {});
              _markAsChanged();
              Navigator.pop(context);
              widget.onRouteUpdated();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
