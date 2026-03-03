# coding=utf-8
"""
    @Author：零 若
    @file： app.py
    @date：2025/10/29 21:09
    @Python  : 3.10.18
    别放弃，即使前方荆棘成林！
"""

import json
import os

from flask import Flask, render_template, request, jsonify

from api_client import BusAPI
from proxy_capture import ProxyCaptureServer
from task_manager import TaskManager

app = Flask(__name__)
app.secret_key = os.urandom(24)

# 全局任务管理器
task_manager = TaskManager()

# 全局代理服务器(单例)
proxy_server = None

# 配置文件路径
CONFIG_FILE = 'config.json'
PRIORITIES_FILE = 'seat_priorities.json'  # 新增:座位优先级配置文件


def load_config():
    """加载配置"""
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
            return json.load(f)
    return {
        'API_HOST': 'hqapp1.bit.edu.cn',
        'API_TOKEN': '',
        'API_TIME': '',
        'USER_ID': ''
    }


def save_config(config):
    """保存配置"""
    with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
        json.dump(config, f, indent=2, ensure_ascii=False)


@app.route('/')
def index():
    """主页"""
    return render_template('index.html')


@app.route('/api/search', methods=['POST'])
def search_buses():
    """车辆查询"""
    try:
        data = request.json
        origin = data.get('origin')
        destination = data.get('destination')
        date = data.get('date')

        if not all([origin, destination, date]):
            return jsonify({'success': False, 'error': '缺少必要参数'})

        config = load_config()

        # 验证配置
        if not config.get('API_HOST'):
            return jsonify({'success': False, 'error': '请先在设置中配置 API 地址'})

        if not config.get('API_TOKEN'):
            return jsonify({'success': False, 'error': '请先在设置中配置 API Token'})

        if not config.get('USER_ID'):
            return jsonify({'success': False, 'error': '请先在设置中配置用户ID'})

        # 调用查询接口
        with BusAPI(config) as api:
            buses = api.search_buses(origin, destination, date)

        return jsonify({'success': True, 'data': buses})

    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})


@app.route('/api/seats/<bus_id>')
def get_seats(bus_id):
    """获取座位信息"""
    try:
        date = request.args.get('date')

        if not date:
            return jsonify({'success': False, 'error': '缺少日期参数'})

        config = load_config()

        with BusAPI(config) as api:
            seats_info = api.get_seats(bus_id, date)

        return jsonify({'success': True, 'data': seats_info})

    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})


@app.route('/api/reserve', methods=['POST'])
def reserve_ticket():
    """预定车票"""
    try:
        data = request.json
        bus_id = data.get('bus_id')
        bus_info = data.get('bus_info', {})
        seat_ids = data.get('seat_ids', [])
        auto_mode = data.get('auto_mode', False)
        target_count = data.get('target_count', 1)
        seat_priorities = data.get('seat_priorities', {})  # 新增：座位优先级

        if not bus_id:
            return jsonify({'success': False, 'error': '缺少班车ID'})

        if not auto_mode and not seat_ids:
            return jsonify({'success': False, 'error': '请至少选择一个座位'})

        config = load_config()

        # 验证配置
        if not config.get('API_HOST') or not config.get('API_TOKEN') or not config.get('USER_ID'):
            return jsonify({'success': False, 'error': '请先完成系统配置'})

        # 创建抢票任务
        task_id = task_manager.create_task(
            bus_id=bus_id,
            bus_info=bus_info,
            seat_ids=seat_ids,
            auto_mode=auto_mode,
            target_count=target_count,
            config=config,
            seat_priorities=seat_priorities  # 传递优先级配置
        )

        return jsonify({'success': True, 'task_id': task_id})

    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})


@app.route('/api/tasks')
def get_tasks():
    """获取任务列表"""
    try:
        tasks = task_manager.get_all_tasks()
        return jsonify({'success': True, 'data': tasks})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})


@app.route('/api/tasks/<task_id>', methods=['DELETE'])
def delete_task(task_id):
    """删除任务"""
    try:
        task_manager.delete_task(task_id)
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})


@app.route('/api/tasks/<task_id>/cancel', methods=['POST'])
def cancel_task(task_id):
    """取消任务"""
    try:
        task_manager.cancel_task(task_id)
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})


@app.route('/api/config', methods=['GET', 'POST'])
def manage_config():
    """配置管理"""
    if request.method == 'GET':
        config = load_config()
        return jsonify({'success': True, 'data': config})
    else:
        try:
            config = request.json

            # 验证必要字段
            required_fields = ['API_HOST', 'API_TOKEN', 'API_TIME', 'USER_ID']
            missing_fields = [f for f in required_fields if not config.get(f)]

            if missing_fields:
                return jsonify({
                    'success': False,
                    'error': f'缺少必要配置: {", ".join(missing_fields)}'
                })

            # 验证 API_TOKEN 长度（应为32位）
            if len(config['API_TOKEN'].strip()) != 32:
                return jsonify({'success': False, 'error': 'API Token 必须是32位字符'})

            # 验证 API_TIME 长度（应为13位时间戳）
            if len(config['API_TIME'].strip()) != 13:
                return jsonify({'success': False, 'error': 'API Time 必须是13位时间戳'})

            save_config(config)
            return jsonify({'success': True, 'message': '配置保存成功'})

        except Exception as e:
            return jsonify({'success': False, 'error': str(e)})


@app.route('/api/proxy/start', methods=['POST'])
def start_proxy():
    """启动代理服务器"""
    global proxy_server

    try:
        if proxy_server and proxy_server.is_running:
            return jsonify({
                'success': False,
                'error': '代理服务器已在运行中'
            })

        # 创建并启动代理服务器
        proxy_server = ProxyCaptureServer(host='0.0.0.0', port=8888)
        proxy_server.start()

        return jsonify({
            'success': True,
            'message': '代理服务器已启动',
            'local_ip': proxy_server.get_local_ip(),
            'port': proxy_server.port
        })

    except Exception as e:
        return jsonify({
            'success': False,
            'error': f'启动失败: {str(e)}'
        })


@app.route('/api/proxy/stop', methods=['POST'])
def stop_proxy():
    """停止代理服务器"""
    global proxy_server

    try:
        if not proxy_server or not proxy_server.is_running:
            return jsonify({
                'success': False,
                'error': '代理服务器未运行'
            })

        proxy_server.stop()
        proxy_server = None

        return jsonify({
            'success': True,
            'message': '代理服务器已停止'
        })

    except Exception as e:
        return jsonify({
            'success': False,
            'error': f'停止失败: {str(e)}'
        })


@app.route('/api/proxy/status')
def proxy_status():
    """获取代理服务器状态"""
    global proxy_server

    if not proxy_server:
        return jsonify({
            'success': True,
            'is_running': False,
            'credentials': None
        })

    credentials = proxy_server.get_credentials()

    return jsonify({
        'success': True,
        'is_running': proxy_server.is_running,
        'credentials': credentials,
        'is_complete': proxy_server.is_credentials_complete(),
        'local_ip': proxy_server.get_local_ip() if proxy_server.is_running else None,
        'port': proxy_server.port if proxy_server.is_running else None
    })


@app.route('/api/proxy/apply', methods=['POST'])
def apply_proxy_credentials():
    """应用捕获的凭证到配置"""
    global proxy_server

    try:
        if not proxy_server or not proxy_server.is_credentials_complete():
            return jsonify({
                'success': False,
                'error': '凭证未完整捕获'
            })

        credentials = proxy_server.get_credentials()

        # 加载现有配置
        config = load_config()

        # 更新凭证
        config['API_TOKEN'] = credentials['API_TOKEN']
        config['API_TIME'] = credentials['API_TIME']
        config['USER_ID'] = credentials['USER_ID']

        # 保存配置
        save_config(config)

        return jsonify({
            'success': True,
            'message': '凭证已应用到配置',
            'config': config
        })

    except Exception as e:
        return jsonify({
            'success': False,
            'error': f'应用失败: {str(e)}'
        })


@app.route('/api/priorities', methods=['GET', 'POST'])
def manage_priorities():
    """座位优先级管理"""
    if request.method == 'GET':
        # 加载优先级配置
        if os.path.exists(PRIORITIES_FILE):
            with open(PRIORITIES_FILE, 'r', encoding='utf-8') as f:
                priorities = json.load(f)
        else:
            # 默认优先级:所有座位为中等优先级
            priorities = {}
            for i in range(1, 52):
                if i not in [1, 2, 49]:
                    priorities[str(i)] = 2  # 1=高, 2=中, 3=低

        return jsonify({'success': True, 'data': priorities})
    else:
        # 保存优先级配置
        try:
            priorities = request.json

            with open(PRIORITIES_FILE, 'w', encoding='utf-8') as f:
                json.dump(priorities, f, indent=2, ensure_ascii=False)

            return jsonify({'success': True, 'message': '优先级配置保存成功'})
        except Exception as e:
            return jsonify({'success': False, 'error': str(e)})


if __name__ == '__main__':
    app.run(debug=False, host='0.0.0.0', port=23200)
