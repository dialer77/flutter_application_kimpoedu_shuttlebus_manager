import 'package:flutter/material.dart';
import '../services/route_manager.dart';
import '../models/route_info.dart';

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
  final TextEditingController _groupNameController = TextEditingController();

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
            ...routes.map((route) => _buildVehicleListTile(route, groupName)),
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
      case 'move':
        _showMoveVehicleDialog(route, groupName);
        break;
      case 'toggle_active':
        setState(() {
          route.isActive = !route.isActive;
        });
        widget.onRouteUpdated();
        break;
      case 'delete':
        _showDeleteVehicleDialog(route, groupName);
        break;
    }
  }

  // 새 그룹 추가 다이얼로그
  void _showAddGroupDialog() {
    _groupNameController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('새 그룹 추가'),
        content: TextField(
          controller: _groupNameController,
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
            onPressed: () {
              final groupName = _groupNameController.text.trim();
              if (groupName.isNotEmpty) {
                setState(() {
                  widget.routeManager.createGroup(groupName);
                });
                Navigator.pop(context);
                widget.onRouteUpdated();
              }
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }

  // 그룹 이름 변경 다이얼로그
  void _showRenameGroupDialog(String oldName) {
    _groupNameController.text = oldName;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('그룹 이름 변경'),
        content: TextField(
          controller: _groupNameController,
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
            onPressed: () {
              final newName = _groupNameController.text.trim();
              if (newName.isNotEmpty && newName != oldName) {
                final success = widget.routeManager.renameGroup(oldName, newName);
                if (success) {
                  setState(() {});
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
              }
            },
            child: const Text('변경'),
          ),
        ],
      ),
    );
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              final vehicleName = nameController.text.trim();
              if (vehicleName.isNotEmpty) {
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
                Navigator.pop(context);
                widget.onRouteUpdated();
              }
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );
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
                      setState(() {});
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
    _groupNameController.dispose();
    super.dispose();
  }
}
