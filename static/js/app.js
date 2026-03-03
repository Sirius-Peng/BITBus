// 全局变量
let currentBusId = null;
let currentBusInfo = null;
let currentDate = null;
let selectedSeats = new Set();
let isPriorityMode = false;

// 路线配置
const ROUTE_CONFIG = {
    '良乡校区->中关村校区': {
        origin: '良乡校区',
        destination: '中关村校区'
    },
    '中关村校区->良乡校区': {
        origin: '中关村校区',
        destination: '良乡校区'
    },
    '中关村校区->西山校区': {
        origin: '中关村校区',
        destination: '西山校区'
    },
    '西山校区->中关村校区': {
        origin: '西山校区',
        destination: '中关村校区'
    },
    '中关村校区->回龙观': {
        origin: '中关村校区',
        destination: '回龙观'
    },
    '回龙观->中关村校区': {
        origin: '回龙观',
        destination: '中关村校区'
    },
    '中关村校区->房山分校阎村': {
        origin: '中关村校区',
        destination: '房山分校阎村'
    },
    '房山分校阎村->中关村校区': {
        origin: '房山分校阎村',
        destination: '中关村校区'
    },
    '良乡校区->回龙观': {
        origin: '良乡校区',
        destination: '回龙观'
    },
    '回龙观->良乡校区': {
        origin: '回龙观',
        destination: '良乡校区'
    }
};

// 座位布局配置
const SEAT_LAYOUT = [
    [1, null, null, null, 2],
    [3, 4, null, 5, 6],
    [7, 8, null, 9, 10],
    [11, 12, null, 13, 14],
    [15, 16, null, 17, 18],
    [19, 20, null, 21, 22],
    [23, 24, null, 25, 26],
    [27, 28, null, null, null],
    [29, 30, null, null, null],
    [31, 32, null, 33, 34],
    [35, 36, null, 37, 38],
    [39, 40, null, 41, 42],
    [43, 44, null, 45, 46],
    [47, 48, 49, 50, 51]
];

// 默认座位优先级配置
let seatPriorities = {}

// 配置缓存（用于取消时恢复）
let configCache = null;

// 代理捕获相关变量
let proxyCheckInterval = null;
let proxyModal = null;
let autoCloseTimer = null;

// 页面加载时初始化
document.addEventListener('DOMContentLoaded', function () {
    // 设置默认日期为今天
    document.getElementById('date').valueAsDate = new Date();

    // 加载配置
    loadConfig();

    // 加载任务列表
    refreshTasks();

    // 加载座位优先级配置(从服务器)
    loadSeatPriorities();

    // 自动抢票模式切换
    document.getElementById('autoMode').addEventListener('change', function (e) {
        document.getElementById('targetCountGroup').style.display =
            e.target.checked ? 'block' : 'none';
    });

    // 支持回车键查询
    document.getElementById('routeDirection').addEventListener('keypress', function (e) {
        if (e.key === 'Enter') {
            e.preventDefault();
            searchBuses();
        }
    });

    document.getElementById('date').addEventListener('keypress', function (e) {
        if (e.key === 'Enter') {
            e.preventDefault();
            searchBuses();
        }
    });

    // 定时刷新任务列表
    setInterval(refreshTasks, 5000);

    // 监听配置模态框的显示事件，保存当前配置
    const configModal = document.getElementById('configModal');
    configModal.addEventListener('show.bs.modal', function () {
        saveConfigCache();
    });

    // 监听配置模态框的关闭事件
    configModal.addEventListener('hidden.bs.modal', function () {
        // 如果用户点击取消按钮，恢复配置
        // 注意：保存成功后 configCache 会被清空
        if (configCache) {
            restoreConfigCache();
        }
    });

    // 取消按钮事件
    const cancelButton = configModal.querySelector('.btn-secondary[data-bs-dismiss="modal"]');
    if (cancelButton) {
        cancelButton.addEventListener('click', function () {
            restoreConfigCache();
        });
    }

    // 监听代理捕获模态框关闭事件
    const proxyCaptureModalElement = document.getElementById('proxyCaptureModal');
    if (proxyCaptureModalElement) {
        proxyCaptureModalElement.addEventListener('hidden.bs.modal', function () {
            // 模态框关闭时自动停止代理服务器
            stopProxyCapture();
        });
    }
});

// 加载座位优先级配置(从服务器)
async function loadSeatPriorities() {
    try {
        const response = await fetch('/api/priorities');
        const result = await response.json();

        if (result.success) {
            seatPriorities = result.data;
        } else {
            console.error('加载座位优先级失败:', result.error);
            // 使用默认配置
            initDefaultPriorities();
        }
    } catch (error) {
        console.error('加载座位优先级失败:', error);
        // 使用默认配置
        initDefaultPriorities();
    }
}

// 初始化默认优先级配置
function initDefaultPriorities() {
    seatPriorities = {};
    for (let i = 1; i <= 51; i++) {
        if (![1, 2, 49].includes(i)) {
            seatPriorities[i] = 2; // 1=高, 2=中, 3=低
        }
    }
}

// 保存座位优先级配置(到服务器)
async function saveSeatPriorities() {
    try {
        const response = await fetch('/api/priorities', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify(seatPriorities)
        });

        const result = await response.json();

        if (!result.success) {
            console.error('保存座位优先级失败:', result.error);
        }
    } catch (error) {
        console.error('保存座位优先级失败:', error);
    }
}

// 更新已选座位显示
function updateSelectedSeats() {
    const display = document.getElementById('selectedSeats');
    if (selectedSeats.size === 0) {
        display.textContent = '无';
    } else {
        display.textContent = Array.from(selectedSeats).sort((a, b) => a - b).join(', ');
    }
}

// 切换座位选择
function toggleSeat(seatId) {
    if (selectedSeats.has(seatId)) {
        selectedSeats.delete(seatId);
    } else {
        selectedSeats.add(seatId);
    }

    const seatElement = document.querySelector(`[data-seat-id="${seatId}"]`);
    if (seatElement) {
        seatElement.classList.toggle('selected');
    }

    updateSelectedSeats();
}

// ==================== Toast 通知系统 ====================

class ToastManager {
    constructor() {
        this.container = this.createContainer();
    }

    createContainer() {
        let container = document.querySelector('.toast-container');
        if (!container) {
            container = document.createElement('div');
            container.className = 'toast-container';
            document.body.appendChild(container);
        }
        return container;
    }

    show(message, type = 'info', duration = 3000) {
        const toast = document.createElement('div');
        toast.className = `custom-toast toast-${type}`;

        const icons = {
            success: 'bi-check-circle-fill',
            error: 'bi-x-circle-fill',
            warning: 'bi-exclamation-triangle-fill',
            info: 'bi-info-circle-fill'
        };

        const titles = {
            success: '成功',
            error: '错误',
            warning: '警告',
            info: '提示'
        };

        toast.innerHTML = `
            <i class="bi ${icons[type]} toast-icon"></i>
            <div class="toast-content">
                <div class="toast-title">${titles[type]}</div>
                <div class="toast-message">${message}</div>
            </div>
            <button class="toast-close" onclick="this.parentElement.remove()">
                <i class="bi bi-x"></i>
            </button>
        `;

        this.container.appendChild(toast);

        // 自动关闭
        if (duration > 0) {
            setTimeout(() => {
                toast.style.animation = 'slideOutRight 0.3s ease';
                setTimeout(() => toast.remove(), 300);
            }, duration);
        }

        return toast;
    }

    success(message, duration) {
        return this.show(message, 'success', duration);
    }

    error(message, duration) {
        return this.show(message, 'error', duration);
    }

    warning(message, duration) {
        return this.show(message, 'warning', duration);
    }

    info(message, duration) {
        return this.show(message, 'info', duration);
    }
}

// 创建全局 Toast 实例
const toast = new ToastManager();

// ==================== 确认对话框 ====================

function showConfirm(message, title = '确认操作') {
    return new Promise((resolve) => {
        const overlay = document.createElement('div');
        overlay.className = 'custom-confirm-overlay';

        overlay.innerHTML = `
            <div class="custom-confirm-dialog">
                <div class="custom-confirm-header">
                    <i class="bi bi-question-circle icon"></i>
                    <div class="title">${title}</div>
                </div>
                <div class="custom-confirm-body">
                    ${message}
                </div>
                <div class="custom-confirm-footer">
                    <button class="btn btn-secondary btn-cancel">
                        <i class="bi bi-x-circle"></i> 取消
                    </button>
                    <button class="btn btn-primary btn-confirm">
                        <i class="bi bi-check-circle"></i> 确认
                    </button>
                </div>
            </div>
        `;

        document.body.appendChild(overlay);

        const dialog = overlay.querySelector('.custom-confirm-dialog');
        const btnCancel = overlay.querySelector('.btn-cancel');
        const btnConfirm = overlay.querySelector('.btn-confirm');

        const close = (result) => {
            overlay.style.animation = 'fadeOut 0.2s ease';
            dialog.style.animation = 'scaleOut 0.2s ease';
            setTimeout(() => {
                overlay.remove();
                resolve(result);
            }, 200);
        };

        btnCancel.onclick = () => close(false);
        btnConfirm.onclick = () => close(true);

        // 点击遮罩关闭
        overlay.onclick = (e) => {
            if (e.target === overlay) {
                close(false);
            }
        };
    });
}

// 显示提示信息
function showAlert(message, type = 'info') {
    const alertHtml = `
        <div class="alert alert-${type} alert-dismissible fade show" role="alert">
            <i class="bi bi-${type === 'success' ? 'check-circle' : type === 'danger' ? 'exclamation-circle' : type === 'warning' ? 'exclamation-triangle' : 'info-circle'}"></i>
            ${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
    `;

    const container = document.getElementById('busResults');
    container.insertAdjacentHTML('afterbegin', alertHtml);

    // 5秒后自动关闭
    setTimeout(() => {
        const alerts = container.querySelectorAll('.alert');
        if (alerts.length > 0) {
            alerts[0].remove();
        }
    }, 5000);
}

// 显示Toast提示 (辅助函数)
function showToast(message, type = 'info') {
    toast.show(message, type);
}

// 查询车辆 - 全局函数
window.searchBuses = async function () {
    const routeDirection = document.getElementById('routeDirection').value;
    const date = document.getElementById('date').value;
    const resultsContainer = document.getElementById('busResults');

    if (!routeDirection) {
        resultsContainer.innerHTML = '';
        toast.warning('请选择线路方向');
        return;
    }

    if (!date) {
        resultsContainer.innerHTML = '';
        toast.warning('请选择日期');
        return;
    }

    const route = ROUTE_CONFIG[routeDirection];
    if (!route) {
        resultsContainer.innerHTML = '';
        toast.error('无效的线路方向');
        return;
    }

    currentDate = date;
    const origin = route.origin;
    const destination = route.destination;

    resultsContainer.innerHTML = `
        <div class="text-center p-5">
            <div class="spinner-border text-primary" role="status">
                <span class="visually-hidden">加载中...</span>
            </div>
            <p class="mt-3">正在查询班车信息...</p>
        </div>
    `;

    try {
        const response = await fetch('/api/search', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({origin, destination, date})
        });

        const result = await response.json();

        if (result.success) {
            displayBuses(result.data);
        } else {
            toast.error('查询失败: ' + result.error);
            resultsContainer.innerHTML = '';
        }
    } catch (error) {
        toast.error('查询失败: ' + error.message);
        resultsContainer.innerHTML = '';
    }
};

// 显示车辆列表
function displayBuses(buses) {
    const container = document.getElementById('busResults');

    if (buses.length === 0) {
        container.innerHTML = `
            <div class="alert alert-info">
                <i class="bi bi-info-circle"></i> 暂无车辆信息
            </div>
        `;
        return;
    }

    container.innerHTML = buses.map(bus => {
        const busJson = JSON.stringify(bus).replace(/"/g, '&quot;');
        return `
            <div class="card bus-card mb-3">
                <div class="card-body">
                    <div class="row align-items-center">
                        <div class="col-md-8">
                            <h5 class="card-title">
                                <i class="bi bi-geo-alt-fill text-success"></i> 
                                ${bus.origin_address} 
                                <i class="bi bi-arrow-right"></i> 
                                ${bus.end_address}
                            </h5>
                            <div class="row mt-3">
                                <div class="col-6">
                                    <small class="text-muted">出发时间</small>
                                    <div><strong>${bus.origin_time}</strong></div>
                                </div>
                                <div class="col-6">
                                    <small class="text-muted">到达时间</small>
                                    <div><strong>${bus.end_time}</strong></div>
                                </div>
                            </div>
                            <div class="mt-2">
                                <span class="badge bg-primary">学生票价: ¥${bus.student_ticket_price}</span>
                                ${bus.type === 1 ? '<span class="badge bg-warning">彩虹班车，需微信公众号预约</span>' : ''}
                            </div>
                        </div>
                        <div class="col-md-4 text-end">
                            ${bus.type === 1 ?
            `<button class="btn btn-secondary" disabled>
                                    <i class="bi bi-wechat"></i> 请到微信公众号预约
                                </button>` :
            `<button class="btn btn-primary btn-lg" onclick='openSeatSelection(${busJson})'>
                                    <i class="bi bi-grid-3x3"></i> 选座
                                </button>`
        }
                        </div>
                    </div>
                </div>
            </div>
        `;
    }).join('');
}

// 打开选座页面 - 全局函数
window.openSeatSelection = async function (busInfo) {
    currentBusId = busInfo.id;
    currentBusInfo = busInfo;
    selectedSeats.clear();

    try {
        const response = await fetch(`/api/seats/${busInfo.id}?date=${currentDate}`);
        const result = await response.json();

        if (result.success) {
            displaySeats(result.data);
            new bootstrap.Modal(document.getElementById('seatModal')).show();
        } else {
            toast.error(result.error || '获取座位信息失败');
        }
    } catch (error) {
        toast.error('网络请求失败: ' + error.message);
    }
};

// 显示座位
function displaySeats(data) {
    const reservedCount = data.reserved_count || 0;
    const availableCount = data.available_count || 0;

    document.getElementById('reservedCount').textContent = reservedCount;
    document.getElementById('availableCount').textContent = availableCount;

    const seatMap = document.getElementById('seatMap');
    const oldLegend = seatMap.parentElement.querySelector('.seat-legend');
    if (oldLegend) oldLegend.remove();

    const legend = document.createElement('div');
    legend.className = 'seat-legend mb-3';
    legend.innerHTML = `
        <div class="d-flex gap-3 flex-wrap justify-content-center">
            <div class="legend-item"><span class="seat-sample available"></span><small>可选座位</small></div>
            <div class="legend-item"><span class="seat-sample reserved"></span><small>已被预订</small></div>
            <div class="legend-item"><span class="seat-sample disabled"></span><small>系统保留</small></div>
            <div class="legend-item"><span class="seat-sample selected"></span><small>已选中</small></div>
            <div class="legend-item"><span class="seat-sample" style="position: relative;"><span class="seat-priority high" style="position: absolute; top: -5px; right: -5px;">H</span></span><small>高优先级</small></div>
            <div class="legend-item"><span class="seat-sample" style="position: relative;"><span class="seat-priority low" style="position: absolute; top: -5px; right: -5px;">L</span></span><small>低优先级</small></div>
        </div>
    `;
    seatMap.parentElement.insertBefore(legend, seatMap);
    seatMap.innerHTML = '';

    const seatMap_data = {};
    data.seats.forEach(seat => {
        seatMap_data[seat.id] = seat;
    });

    SEAT_LAYOUT.forEach(row => {
        row.forEach(seatNum => {
            const seatElement = document.createElement('div');
            seatElement.className = 'seat';

            if (seatNum === null) {
                // 空位置（过道）
                seatElement.classList.add('empty');
            } else {
                seatElement.textContent = seatNum;
                seatElement.dataset.seatId = seatNum;

                const seat = seatMap_data[seatNum];

                if (seat) {
                    if (seat.status === 'disabled') {
                        seatElement.classList.add('disabled');
                        seatElement.title = seat.reason || '系统保留座位';
                        // 禁用座位不允许设置优先级
                    } else if (seat.status === 'reserved') {
                        seatElement.classList.add('reserved');
                        seatElement.title = `${seat.reason || '已被预订'} - 右键可设置优先级`;

                        // 已预订的座位也可以设置优先级（用于候补）
                        seatElement.addEventListener('contextmenu', (e) => {
                            e.preventDefault();
                            showPriorityMenu(e, seatNum, seatElement, true);
                        });

                        // 添加优先级标识
                        const priority = seatPriorities[seatNum] || 2;
                        if (priority !== 2) {
                            const priorityBadge = document.createElement('span');
                            priorityBadge.className = `seat-priority ${priority === 1 ? 'high' : 'low'}`;
                            priorityBadge.textContent = priority === 1 ? 'H' : 'L';
                            priorityBadge.title = priority === 1 ? '高优先级（候补）' : '低优先级（候补）';
                            seatElement.appendChild(priorityBadge);
                        }
                    } else if (seat.status === 'available') {
                        seatElement.classList.add('available');
                        seatElement.title = `座位 ${seatNum} - 点击选择 | 右键设置优先级`;

                        // 左键点击选择座位
                        seatElement.addEventListener('click', (e) => {
                            e.preventDefault();
                            if (!isPriorityMode) {
                                toggleSeat(seatNum);
                            }
                        });

                        // 右键菜单设置优先级
                        seatElement.addEventListener('contextmenu', (e) => {
                            e.preventDefault();
                            showPriorityMenu(e, seatNum, seatElement, false);
                        });

                        // 添加优先级标识
                        const priority = seatPriorities[seatNum] || 2;
                        if (priority !== 2) {
                            const priorityBadge = document.createElement('span');
                            priorityBadge.className = `seat-priority ${priority === 1 ? 'high' : 'low'}`;
                            priorityBadge.textContent = priority === 1 ? 'H' : 'L';
                            priorityBadge.title = priority === 1 ? '高优先级' : '低优先级';
                            seatElement.appendChild(priorityBadge);
                        }
                    }
                }
            }

            seatMap.appendChild(seatElement);
        });
    });

    updateSelectedSeats();
}

// 显示优先级菜单
function showPriorityMenu(event, seatNum, seatElement, isReserved = false) {
    // 移除已存在的菜单
    const existingMenu = document.querySelector('.priority-menu');
    if (existingMenu) {
        existingMenu.remove();
    }

    // 创建菜单
    const menu = document.createElement('div');
    menu.className = 'priority-menu';
    menu.style.cssText = `position: fixed; left: ${event.clientX}px; top: ${event.clientY}px; z-index: 9999;`;

    const currentPriority = seatPriorities[seatNum] || 2;

    menu.innerHTML = `
        <div class="card shadow-sm" style="min-width: 180px;">
            <div class="card-body p-2">
                <div class="small text-muted mb-2">
                    座位 ${seatNum} ${isReserved ? '(已被预订)' : ''}<br>
                    设置优先级${isReserved ? '（候补）' : ''}
                </div>
                <div class="list-group list-group-flush">
                    <button class="list-group-item list-group-item-action ${currentPriority === 1 ? 'active' : ''}" 
                            onclick="setPriority(${seatNum}, 1, ${isReserved})">
                        <i class="bi bi-star-fill text-danger"></i> 高优先级
                    </button>
                    <button class="list-group-item list-group-item-action ${currentPriority === 2 ? 'active' : ''}" 
                            onclick="setPriority(${seatNum}, 2, ${isReserved})">
                        <i class="bi bi-star-half text-warning"></i> 中优先级
                    </button>
                    <button class="list-group-item list-group-item-action ${currentPriority === 3 ? 'active' : ''}" 
                            onclick="setPriority(${seatNum}, 3, ${isReserved})">
                        <i class="bi bi-star text-secondary"></i> 低优先级
                    </button>
                </div>
                ${isReserved ? '<small class="text-muted d-block mt-2 px-2">他人退票时按此优先级抢座</small>' : ''}
            </div>
        </div>
    `;

    document.body.appendChild(menu);

    // 点击其他地方关闭菜单
    setTimeout(() => {
        document.addEventListener('click', function closeMenu(e) {
            if (!menu.contains(e.target)) {
                menu.remove();
                document.removeEventListener('click', closeMenu);
            }
        });
    }, 100);
}

// 设置单个座位优先级 - 全局函数
window.setPriority = function (seatNum, priority, isReserved = false) {
    seatPriorities[seatNum] = priority;
    saveSeatPriorities(); // 保存到服务器

    const seatElement = document.querySelector(`[data-seat-id="${seatNum}"]`);
    if (seatElement) {
        const oldBadge = seatElement.querySelector('.seat-priority');
        if (oldBadge) oldBadge.remove();

        if (priority !== 2) {
            const priorityBadge = document.createElement('span');
            priorityBadge.className = `seat-priority ${priority === 1 ? 'high' : 'low'}`;
            priorityBadge.textContent = priority === 1 ? 'H' : 'L';
            priorityBadge.title = priority === 1 ? (isReserved ? '高优先级（候补）' : '高优先级') : (isReserved ? '低优先级（候补）' : '低优先级');
            seatElement.appendChild(priorityBadge);
        }

        const seatStatus = seatElement.classList.contains('reserved') ? '已被预订' : seatElement.classList.contains('available') ? '可选' : '';
        if (seatStatus) {
            seatElement.title = `座位 ${seatNum} (${seatStatus}) - ${priority === 1 ? '高优先级' : priority === 2 ? '中优先级' : '低优先级'}`;
        }
    }

    const menu = document.querySelector('.priority-menu');
    if (menu) menu.remove();

    const priorityText = priority === 1 ? '高' : priority === 2 ? '中' : '低';
    const statusText = isReserved ? '（候补）' : '';
    toast.info(`座位 ${seatNum} 优先级已设置为${priorityText}${statusText}`);
};

// 批量设置优先级 - 全局函数
window.batchSetPriority = function (priority) {
    // 记录当前滚动位置 - 查找正确的滚动容器
    const modalBody = document.querySelector('#seatModal .modal-body');
    const scrollPosition = modalBody ? modalBody.scrollTop : 0;

    for (let i = 3; i <= 51; i++) {
        if (![1, 2, 49].includes(i)) {
            seatPriorities[i] = priority;

            // 直接更新座位显示，不重新加载数据
            const seatElement = document.querySelector(`[data-seat-id="${i}"]`);
            if (seatElement && !seatElement.classList.contains('disabled')) {
                const oldBadge = seatElement.querySelector('.seat-priority');
                if (oldBadge) oldBadge.remove();
                if (priority !== 2) {
                    const isReserved = seatElement.classList.contains('reserved');
                    const priorityBadge = document.createElement('span');
                    priorityBadge.className = `seat-priority ${priority === 1 ? 'high' : 'low'}`;
                    priorityBadge.textContent = priority === 1 ? 'H' : 'L';
                    priorityBadge.title = priority === 1 ? (isReserved ? '高优先级（候补）' : '高优先级') : (isReserved ? '低优先级（候补）' : '低优先级');
                    seatElement.appendChild(priorityBadge);
                }
            }
        }
    }
    saveSeatPriorities(); // 保存到服务器
    if (modalBody) {
        requestAnimationFrame(() => {
            modalBody.scrollTop = scrollPosition;
        });
    }
    const priorityText = priority === 1 ? '高' : priority === 2 ? '中' : '低';
    toast.info(`所有座位优先级已设置为${priorityText}`);
};

// 确认预定 - 全局函数
window.confirmReservation = async function () {
    const autoMode = document.getElementById('autoMode').checked;
    const targetCount = parseInt(document.getElementById('targetCount').value) || 1;

    if (!autoMode && selectedSeats.size === 0) {
        toast.warning('请至少选择一个座位');
        return;
    }
    if (!currentDate) {
        toast.error('未找到查询日期，请重新查询');
        return;
    }

    try {
        const response = await fetch('/api/reserve', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({
                bus_id: currentBusId,
                bus_info: {
                    origin_address: currentBusInfo.origin_address,
                    end_address: currentBusInfo.end_address,
                    origin_time: currentBusInfo.origin_time,
                    end_time: currentBusInfo.end_time,
                    date: currentDate
                },
                seat_ids: Array.from(selectedSeats),
                auto_mode: autoMode,
                target_count: targetCount,
                seat_priorities: seatPriorities
            })
        });

        const result = await response.json();

        if (result.success) {
            toast.success('抢票任务已创建！系统将自动开始抢票', 4000);
            bootstrap.Modal.getInstance(document.getElementById('seatModal')).hide();
            document.getElementById('tasks-tab').click();
            refreshTasks();
        } else {
            toast.error(result.error || '创建任务失败');
        }
    } catch (error) {
        toast.error('网络请求失败: ' + error.message);
    }
};

// 刷新任务列表 - 全局函数
window.refreshTasks = async function () {
    try {
        const response = await fetch('/api/tasks');
        const result = await response.json();
        if (result.success) displayTasks(result.data);
    } catch (error) {
        console.error('刷新任务失败:', error);
    }
};

// 显示任务列表
function displayTasks(tasks) {
    const container = document.getElementById('taskList');

    if (tasks.length === 0) {
        container.innerHTML = '<div class="alert alert-info">暂无任务</div>';
        return;
    }

    const statusIcons = {
        pending: 'hourglass-split',
        waiting: 'clock',
        running: 'arrow-repeat',
        success: 'check-circle',
        failed: 'x-circle',
        cancelled: 'dash-circle'
    };

    const statusColors = {
        pending: 'warning',
        waiting: 'info',
        running: 'primary',
        success: 'success',
        failed: 'danger',
        cancelled: 'secondary'
    };

    const statusText = {
        pending: '准备中',
        waiting: '等待开抢',
        running: '抢票中',
        success: '成功',
        failed: '失败',
        cancelled: '已取消'
    };

    container.innerHTML = tasks.map(task => `
        <div class="task-item status-${task.status}">
            <div class="d-flex justify-content-between align-items-start">
                <div class="flex-grow-1">
                    <h6>
                        <i class="bi bi-${statusIcons[task.status] || 'info-circle'}"></i>
                        ${task.bus_info.origin_address || ''} → ${task.bus_info.end_address || ''}
                        <span class="badge bg-${statusColors[task.status] || 'secondary'} status-badge ms-2">
                            ${statusText[task.status] || task.status}
                        </span>
                    </h6>
                    <p class="mb-1 text-muted small">
                        <i class="bi bi-clock"></i> 发车: ${task.bus_info.origin_time || 'N/A'}
                        ${task.start_time ? ` | 开抢: ${task.start_time}` : ''}
                    </p>
                    <p class="mb-1 text-muted small">
                        <i class="bi bi-calendar"></i> 创建: ${task.created_at || 'N/A'}
                    </p>
                    <p class="mb-1">
                        <i class="bi bi-info-circle"></i> ${task.message || '处理中...'}
                    </p>
                    ${task.reserved_seats && task.reserved_seats.length > 0 ?
        `<p class="mb-0">
                            <i class="bi bi-check-circle text-success"></i> 
                            <strong>已预订座位:</strong> ${task.reserved_seats.join(', ')}
                        </p>`
        : ''}
                    <p class="mb-0 text-muted small">
                        <i class="bi bi-gear"></i> 
                        ${task.auto_mode ? `自动模式 (目标${task.target_count || 1}个)` : '手动模式'}
                    </p>
                </div>
                <div class="btn-group">
                    ${task.status === 'running' || task.status === 'waiting' ?
        `<button class="btn btn-sm btn-warning" onclick="cancelTask('${task.task_id}')" title="取消任务">
                            <i class="bi bi-pause-circle"></i>
                        </button>` : ''}
                    <button class="btn btn-sm btn-danger" onclick="deleteTask('${task.task_id}')" title="删除任务">
                        <i class="bi bi-trash"></i>
                    </button>
                </div>
            </div>
        </div>
    `).join('');
}

// 取消任务 - 全局函数
window.cancelTask = async function (taskId) {
    const confirmed = await showConfirm('确定要取消此任务吗？', '取消任务');
    if (!confirmed) return;
    
    try {
        const response = await fetch(`/api/tasks/${taskId}/cancel`, {method: 'POST'});
        const result = await response.json();
        if (result.success) {
            toast.success('任务已取消');
            refreshTasks();
        } else {
            toast.error(result.error || '取消失败');
        }
    } catch (error) {
        toast.error('网络请求失败: ' + error.message);
    }
};

// 删除任务 - 全局函数
window.deleteTask = async function (taskId) {
    const confirmed = await showConfirm('确定要删除此任务吗？删除后无法恢复。', '删除任务');
    if (!confirmed) return;
    
    try {
        const response = await fetch(`/api/tasks/${taskId}`, {method: 'DELETE'});
        const result = await response.json();
        if (result.success) {
            toast.success('任务已删除');
            refreshTasks();
        } else {
            toast.error(result.error || '删除失败');
        }
    } catch (error) {
        toast.error('网络请求失败: ' + error.message);
    }
};

// 加载配置
async function loadConfig() {
    try {
        const response = await fetch('/api/config');
        const result = await response.json();

        if (result.success) {
            const config = result.data;

            // API配置
            document.getElementById('apiHost').value = config.API_HOST || '';
            document.getElementById('apiToken').value = config.API_TOKEN || '';
            document.getElementById('apiTime').value = config.API_TIME || '';
            document.getElementById('userId').value = config.USER_ID || '';

            // 通知配置
            const notificationMethods = config.notification_methods || [];

            // 邮箱配置
            const emailEnabled = notificationMethods.includes('email');
            document.getElementById('enableEmail').checked = emailEnabled;

            if (emailEnabled && config.email_config) {
                document.getElementById('smtpServer').value = config.email_config.smtp_server || 'smtp.qq.com';
                document.getElementById('smtpPort').value = config.email_config.smtp_port || '465';
                document.getElementById('senderEmail').value = config.email_config.sender_email || '';
                document.getElementById('senderPassword').value = config.email_config.sender_password || '';
                document.getElementById('receiverEmail').value = config.email_config.receiver_email || '';
            }

            // 企业微信配置
            const wechatEnabled = notificationMethods.includes('wechat_work');
            document.getElementById('enableWechat').checked = wechatEnabled;

            if (wechatEnabled && config.wechat_config) {
                document.getElementById('wechatWebhook').value = config.wechat_config.webhook_url || '';
            }
        }
    } catch (error) {
        console.error('加载配置失败:', error);
    }
}

// 保存配置缓存
function saveConfigCache() {
    configCache = {
        // API配置
        API_HOST: document.getElementById('apiHost').value,
        API_TOKEN: document.getElementById('apiToken').value,
        API_TIME: document.getElementById('apiTime').value,
        USER_ID: document.getElementById('userId').value,

        // 通知配置
        enableEmail: document.getElementById('enableEmail').checked,
        smtpServer: document.getElementById('smtpServer').value,
        smtpPort: document.getElementById('smtpPort').value,
        senderEmail: document.getElementById('senderEmail').value,
        senderPassword: document.getElementById('senderPassword').value,
        receiverEmail: document.getElementById('receiverEmail').value,

        enableWechat: document.getElementById('enableWechat').checked,
        wechatWebhook: document.getElementById('wechatWebhook').value
    };
}

// 恢复配置缓存
function restoreConfigCache() {
    if (!configCache) return;

    // 恢复 API 配置
    document.getElementById('apiHost').value = configCache.API_HOST;
    document.getElementById('apiToken').value = configCache.API_TOKEN;
    document.getElementById('apiTime').value = configCache.API_TIME;
    document.getElementById('userId').value = configCache.USER_ID;

    // 恢复通知配置
    document.getElementById('enableEmail').checked = configCache.enableEmail;
    document.getElementById('smtpServer').value = configCache.smtpServer;
    document.getElementById('smtpPort').value = configCache.smtpPort;
    document.getElementById('senderEmail').value = configCache.senderEmail;
    document.getElementById('senderPassword').value = configCache.senderPassword;
    document.getElementById('receiverEmail').value = configCache.receiverEmail;

    document.getElementById('enableWechat').checked = configCache.enableWechat;
    document.getElementById('wechatWebhook').value = configCache.wechatWebhook;

    // 清空缓存
    configCache = null;
}

// 保存配置 - 全局函数
window.saveConfig = async function () {
    const config = {
        API_HOST: document.getElementById('apiHost').value.trim() || 'hqapp1.bit.edu.cn',
        API_TOKEN: document.getElementById('apiToken').value.trim(),
        API_TIME: document.getElementById('apiTime').value.trim(),
        USER_ID: document.getElementById('userId').value.trim(),

        notification_methods: [],
        email_config: {},
        wechat_config: {}
    };

    if (document.getElementById('enableEmail').checked) {
        config.notification_methods.push('email');
        config.email_config = {
            smtp_server: document.getElementById('smtpServer').value.trim() || 'smtp.qq.com',
            smtp_port: document.getElementById('smtpPort').value.trim() || '465',
            sender_email: document.getElementById('senderEmail').value.trim(),
            sender_password: document.getElementById('senderPassword').value.trim(),
            receiver_email: document.getElementById('receiverEmail').value.trim()
        };
    }

    if (document.getElementById('enableWechat').checked) {
        config.notification_methods.push('wechat_work');
        config.wechat_config = {
            webhook_url: document.getElementById('wechatWebhook').value.trim()
        };
    }

    // 前端验证
    if (!config.API_TOKEN) {
        toast.warning('请输入 API Token');
        return;
    }

    if (config.API_TOKEN.length !== 32) {
        toast.warning('API Token 必须是32位字符');
        return;
    }

    if (!config.API_TIME) {
        toast.warning('请输入 API Time');
        return;
    }

    if (config.API_TIME.length !== 13) {
        toast.warning('API Time 必须是13位时间戳');
        return;
    }

    if (!config.USER_ID) {
        toast.warning('请输入用户ID');
        return;
    }

    try {
        const response = await fetch('/api/config', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify(config)
        });

        const result = await response.json();

        if (result.success) {
            configCache = null;
            toast.success('配置保存成功！');
            bootstrap.Modal.getInstance(document.getElementById('configModal')).hide();
        } else {
            toast.error(result.error || '保存失败');
        }
    } catch (error) {
        toast.error('网络请求失败: ' + error.message);
    }
};

// 更新凭证状态显示
function updateCredentialStatus(elementId, value) {
    const element = document.getElementById(elementId);
    if (!element) return;

    if (value && value !== null && value !== 'null') {
        const masked = value.length > 8 ?
            value.substring(0, 4) + '***' + value.substring(value.length - 4) :
            value.substring(0, 2) + '***';
        element.innerHTML = `<i class="bi bi-check-circle-fill text-success"></i> ${masked}`;
    } else {
        element.innerHTML = `<i class="bi bi-hourglass text-muted"></i> 等待中`;
    }
}

// 打开代理捕获窗口
window.openProxyCapture = async function () {
    try {
        // 启动代理服务器
        const response = await fetch('/api/proxy/start', {method: 'POST'});
        const result = await response.json();

        if (result.success) {
            // 显示模态框
            proxyModal = new bootstrap.Modal(document.getElementById('proxyCaptureModal'));
            proxyModal.show();

            // 更新配置信息
            document.getElementById('proxyServerIP').textContent = result.local_ip;
            document.getElementById('proxyServerPort').textContent = result.port;

            // 显示配置说明
            document.getElementById('proxyStatus').innerHTML = `
                <div class="alert alert-success">
                    <i class="bi bi-check-circle"></i> 代理服务器已启动
                </div>
            `;
            document.getElementById('proxyInstructions').style.display = 'block';

            // 重置状态
            document.getElementById('applyCredentialsBtn').style.display = 'none';
            updateCredentialStatus('tokenStatus', null);
            updateCredentialStatus('timeStatus', null);
            updateCredentialStatus('useridStatus', null);

            // 为捕获进度卡片添加流动光影效果
            setTimeout(() => {
                const progressCard = document.querySelector('#proxyInstructions .card:last-child');
                if (progressCard) {
                    progressCard.classList.add('shimmer-effect');
                }
            }, 100);

            // 开始轮询检查捕获状态
            startProxyStatusCheck();
        } else {
            toast.error(result.error || '启动代理失败');
        }
    } catch (error) {
        toast.error('网络请求失败: ' + error.message);
    }
};

// 开始检查代理状态
function startProxyStatusCheck() {
    if (proxyCheckInterval) {
        clearInterval(proxyCheckInterval);
    }

    proxyCheckInterval = setInterval(async () => {
        try {
            const response = await fetch('/api/proxy/status');
            const result = await response.json();

            if (result.success && result.credentials) {
                const cred = result.credentials;

                // 更新状态显示
                updateCredentialStatus('tokenStatus', cred.API_TOKEN);
                updateCredentialStatus('timeStatus', cred.API_TIME);
                updateCredentialStatus('useridStatus', cred.USER_ID);

                // 如果全部捕获完成
                if (result.is_complete) {
                    clearInterval(proxyCheckInterval);
                    proxyCheckInterval = null;

                    document.getElementById('proxyStatus').innerHTML = `
                        <div class="alert alert-success">
                            <i class="bi bi-check-circle-fill"></i> 
                            <strong>捕获完成!</strong> 凭证将自动应用到配置中
                        </div>
                    `;

                    const progressCard = document.querySelector('#proxyInstructions .card:last-child');
                    if (progressCard) {
                        progressCard.classList.remove('shimmer-effect');
                    }

                    document.getElementById('applyCredentialsBtn').style.display = 'inline-block';

                    // 自动应用凭证
                    toast.success('凭证捕获完成，正在自动应用...', 2000);

                    setTimeout(async () => {
                        await applyProxyCredentials();

                        // 显示关闭代理提醒
                        showProxyCloseReminder();

                        // 延迟关闭代理和模态框(5秒)
                        autoCloseTimer = setTimeout(async () => {
                            await stopProxyCapture();
                        }, 5000);
                    }, 1000);
                }
            }
        } catch (error) {
            console.error('检查代理状态失败:', error);
        }
    }, 1000);
}

// 显示关闭代理提醒
function showProxyCloseReminder() {
    // 创建提醒对话框
    const reminderHtml = `
        <div class="modal fade" id="proxyReminderModal" tabindex="-1" data-bs-backdrop="static">
            <div class="modal-dialog modal-dialog-centered">
                <div class="modal-content">
                    <div class="modal-header bg-warning text-dark">
                        <h5 class="modal-title">
                            <i class="bi bi-exclamation-triangle-fill"></i> 重要提醒
                        </h5>
                    </div>
                    <div class="modal-body">
                        <div class="alert alert-warning mb-3">
                            <h6 class="alert-heading">
                                <i class="bi bi-wifi-off"></i> 请关闭手机代理设置
                            </h6>
                            <p class="mb-2">凭证已成功捕获并应用，代理服务器将在 <span id="autoCloseCountdown">5</span> 秒后自动关闭。</p>
                            <p class="mb-0"><strong>请立即在手机上关闭代理设置，以恢复正常上网！</strong></p>
                        </div>
                        
                        <div class="card">
                            <div class="card-header bg-light">
                                <strong><i class="bi bi-phone"></i> 关闭步骤：</strong>
                            </div>
                            <div class="card-body">
                                <ol class="mb-0">
                                    <li>打开手机WiFi设置</li>
                                    <li>选择已连接的WiFi</li>
                                    <li>将代理设置改为 <strong>"关闭"</strong> 或 <strong>"无"</strong></li>
                                    <li>保存设置</li>
                                </ol>
                            </div>
                        </div>
                        
                        <div class="mt-3 text-center">
                            <small class="text-muted">
                                <i class="bi bi-info-circle"></i> 
                                不关闭代理可能导致手机无法正常上网
                            </small>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button type="button" class="btn btn-primary" onclick="closeProxyReminder()">
                            <i class="bi bi-check-circle"></i> 我已关闭代理
                        </button>
                    </div>
                </div>
            </div>
        </div>
    `;

    // 添加到页面
    const tempDiv = document.createElement('div');
    tempDiv.innerHTML = reminderHtml;
    document.body.appendChild(tempDiv.firstElementChild);

    // 显示模态框
    const reminderModal = new bootstrap.Modal(document.getElementById('proxyReminderModal'));
    reminderModal.show();

    // 倒计时显示
    let countdown = 5;
    const countdownInterval = setInterval(() => {
        countdown--;
        const countdownElement = document.getElementById('autoCloseCountdown');
        if (countdownElement) {
            countdownElement.textContent = countdown;
        }
        if (countdown <= 0) {
            clearInterval(countdownInterval);
        }
    }, 1000);

    // 播放提示音(如果浏览器支持)
    try {
        const beep = new Audio('data:audio/wav;base64,UklGRnoGAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQoGAACBhYqFbF1fdJivrJBhNjVgodDbq2EcBj+a2/LDciUFLIHO8tiJNwgZaLvt559NEAxQp+PwtmMcBjiR1/LMeSwFJHfH8N2QQAoUXrTp66hVFApGn+DyvmwhBSuBzvLZiTYIGmi87OqgUBELTanm8LhjHQU2jdXzzn0vBSF1xe/glEILElyx6OyrWBUIQ5zd8sFuJAUqgM3y2Ik3CBlouu7pn08RC0yo5O+5YxwGNo3V88x8LgUgdMXv4ZNCDRJZR');
        beep.play().catch(() => {
        });
    } catch (e) {
        // 忽略音频错误
    }
}

// 关闭代理提醒
window.closeProxyReminder = function () {
    const modal = bootstrap.Modal.getInstance(document.getElementById('proxyReminderModal'));
    if (modal) {
        modal.hide();
    }

    // 清除自动关闭定时器
    if (autoCloseTimer) {
        clearTimeout(autoCloseTimer);
        autoCloseTimer = null;
    }

    // 移除模态框元素
    setTimeout(() => {
        const modalElement = document.getElementById('proxyReminderModal');
        if (modalElement) {
            modalElement.remove();
        }
    }, 500);

    toast.success('感谢您的配合！现在可以正常使用系统了 🎉');

    // 立即关闭凭证捕获模态框
    setTimeout(() => {
        stopProxyCapture();
    }, 100); // 稍微延迟一下,让提醒模态框先完成关闭动画
};

// 停止代理捕获
window.stopProxyCapture = async function () {
    try {
        // 停止轮询
        if (proxyCheckInterval) {
            clearInterval(proxyCheckInterval);
            proxyCheckInterval = null;
        }

        // 清除自动关闭定时器
        if (autoCloseTimer) {
            clearTimeout(autoCloseTimer);
            autoCloseTimer = null;
        }

        // 停止代理服务器
        const response = await fetch('/api/proxy/stop', {method: 'POST'});
        const result = await response.json();

        if (!result.success && result.error !== '代理服务器未运行') {
            console.error('停止代理失败:', result.error);
        }

        // 关闭模态框
        if (proxyModal) {
            proxyModal.hide();
            proxyModal = null;
        }
    } catch (error) {
        console.error('停止代理失败:', error);
    }
};

// 应用代理捕获的凭证
window.applyProxyCredentials = async function () {
    try {
        const response = await fetch('/api/proxy/apply', {method: 'POST'});
        const result = await response.json();

        if (result.success) {
            toast.success('凭证已自动填充到配置中！', 3000);

            // 刷新配置显示
            await loadConfig();

            // 不立即关闭，等待自动关闭
            return true;
        } else {
            toast.error(result.error || '应用凭证失败');
            return false;
        }
    } catch (error) {
        toast.error('网络请求失败: ' + error.message);
        return false;
    }
};

// 确保在文件开头就定义所有全局函数
(function () {
    'use strict';

    window.openProxyCapture = async function () {
        try {
            // 启动代理服务器
            const response = await fetch('/api/proxy/start', {method: 'POST'});
            const result = await response.json();

            if (result.success) {
                // 显示模态框
                proxyModal = new bootstrap.Modal(document.getElementById('proxyCaptureModal'));
                proxyModal.show();

                // 更新配置信息
                document.getElementById('proxyServerIP').textContent = result.local_ip;
                document.getElementById('proxyServerPort').textContent = result.port;

                // 显示配置说明
                document.getElementById('proxyStatus').innerHTML = `
                    <div class="alert alert-success">
                        <i class="bi bi-check-circle"></i> 代理服务器已启动
                    </div>
                `;
                document.getElementById('proxyInstructions').style.display = 'block';

                // 重置状态
                document.getElementById('applyCredentialsBtn').style.display = 'none';
                updateCredentialStatus('tokenStatus', null);
                updateCredentialStatus('timeStatus', null);
                updateCredentialStatus('useridStatus', null);

                setTimeout(() => {
                    const progressCard = document.querySelector('#proxyInstructions .card:last-child');
                    if (progressCard) {
                        progressCard.classList.add('shimmer-effect');
                    }
                }, 100);

                // 开始轮询检查捕获状态
                startProxyStatusCheck();
            } else {
                toast.error(result.error || '启动代理失败');
            }
        } catch (error) {
            toast.error('网络请求失败: ' + error.message);
        }
    };

    // 确保在页面卸载时停止代理
    window.addEventListener('beforeunload', function () {
        if (proxyCheckInterval) {
            stopProxyCapture();
        }
    });
})();
