# coding=utf-8
"""
    @Author：零 若
    @file： task_manager.py
    @date：2025/10/29 21:09
    @Python  : 3.10.18
    别放弃，即使前方荆棘成林！
"""

import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta

from api_client import BusAPI


class Task:
    def __init__(self, task_id, bus_id, bus_info, seat_ids, auto_mode, target_count, config, seat_priorities=None):
        self.task_id = task_id
        self.bus_id = bus_id
        self.bus_info = bus_info
        self.seat_ids = seat_ids
        self.auto_mode = auto_mode
        self.target_count = target_count
        self.config = config
        self.status = 'pending'  # pending, waiting, running, success, failed, cancelled
        self.message = ''
        self.created_at = datetime.now()
        self.start_time = None
        self.thread = None
        self.stop_flag = False
        self.reserved_seats = []
        self.seat_priorities = seat_priorities or {}  # 座位优先级配置
        self.lock = threading.Lock()  # 用于保护 reserved_seats
        self.parallel_workers = 5  # 并行工作线程数


class TaskManager:
    def __init__(self):
        self.tasks = {}
        self.lock = threading.Lock()

    def create_task(self, bus_id, bus_info, seat_ids, auto_mode, target_count, config, seat_priorities=None):
        """创建任务"""
        task_id = str(uuid.uuid4())
        task = Task(task_id, bus_id, bus_info, seat_ids, auto_mode, target_count, config, seat_priorities)

        # 计算开抢时间（发车前1小时）
        try:
            origin_time_str = bus_info.get('origin_time', '')  # 格式：HH:MM
            date_str = bus_info.get('date', '')  # 格式：YYYY-MM-DD

            if not date_str:
                # 如果没有日期，使用当前日期
                date_str = datetime.now().strftime('%Y-%m-%d')

            if not origin_time_str:
                raise ValueError('未找到发车时间')

            # 组合日期和时间
            full_datetime_str = f"{date_str} {origin_time_str}"

            # 解析为 datetime 对象
            origin_datetime = datetime.strptime(full_datetime_str, '%Y-%m-%d %H:%M')

            # 计算开抢时间（发车前1小时）
            task.start_time = origin_datetime - timedelta(hours=1)

            # 如果开抢时间已过，立即开始
            if task.start_time <= datetime.now():
                task.start_time = datetime.now()
                task.message = '立即开始抢票'
            else:
                time_diff = task.start_time - datetime.now()
                hours = int(time_diff.total_seconds() // 3600)
                minutes = int((time_diff.total_seconds() % 3600) // 60)

                if hours > 0:
                    task.message = f'等待开抢（还需 {hours}小时{minutes}分钟）'
                else:
                    task.message = f'等待开抢（还需 {minutes}分钟）'

        except Exception as e:
            # 如果时间解析失败，立即开始
            task.start_time = datetime.now()
            task.message = f'时间解析失败，立即开始: {str(e)}'

        with self.lock:
            self.tasks[task_id] = task

        # 启动任务线程
        thread = threading.Thread(target=self._run_task, args=(task,))
        thread.daemon = True
        task.thread = thread
        thread.start()

        return task_id

    def _run_task(self, task):
        """运行任务"""
        api = None
        try:
            api = BusAPI(task.config)

            # 等待到开抢时间
            task.status = 'waiting'
            while datetime.now() < task.start_time and not task.stop_flag:
                time_diff = task.start_time - datetime.now()
                minutes = int(time_diff.total_seconds() / 60)
                seconds = int(time_diff.total_seconds() % 60)
                task.message = f'等待开抢（{minutes}分{seconds}秒后开始）'
                time.sleep(1)

            if task.stop_flag:
                task.status = 'cancelled'
                task.message = '任务已取消'
                return

            task.status = 'running'
            task.message = '正在抢票...'

            # 获取日期信息
            date = task.bus_info.get('date')
            if not date:
                # 尝试从 origin_time 提取日期
                origin_time = task.bus_info.get('origin_time', '')
                if ' ' in origin_time:
                    date = origin_time.split()[0]
                else:
                    date = datetime.now().strftime('%Y-%m-%d')

            if task.auto_mode:
                # 自动模式：并行抢票
                self._parallel_auto_reserve(task, date)
            else:
                # 手动模式：并行抢指定座位
                self._parallel_manual_reserve(task, date)

        except Exception as e:
            task.status = 'failed'
            task.message = f'抢票失败: {str(e)}'
            if api:
                api.send_notification('❌ 抢票失败', task.message)
        finally:
            if api:
                api.close()

    def _reserve_seat_worker(self, task, seat_id, date):
        """
        单个座位预订工作函数（用于并行执行）

        Returns:
            (success: bool, seat_id: int, message: str)
        """
        try:
            # 每个工作线程创建自己的 API 客户端
            api = BusAPI(task.config)

            result = api.reserve_seat(task.bus_id, seat_id, date)

            api.close()

            if result.get('success'):
                return True, seat_id, '预订成功'
            else:
                return False, seat_id, result.get('error', '未知错误')

        except Exception as e:
            return False, seat_id, str(e)

    def _parallel_auto_reserve(self, task, date):
        """
        并行自动抢票模式
        使用线程池同时尝试多个座位
        """
        api = BusAPI(task.config)
        reserved_count = 0
        round_count = 0
        max_rounds = 1000
        tried_seats = set()

        try:
            while reserved_count < task.target_count and round_count < max_rounds and not task.stop_flag:
                round_count += 1

                # 获取座位信息
                seats_info = api.get_seats(task.bus_id, date)

                # 筛选可用且未尝试过的座位
                available_seats = [
                    s['id'] for s in seats_info.get('seats', [])
                    if s.get('status') == 'available' and s['id'] not in tried_seats
                ]

                if not available_seats:
                    task.message = f'暂无可用座位，第 {round_count} 轮尝试...'
                    time.sleep(0.5)

                    # 每 10 轮重置已尝试座位
                    if round_count % 10 == 0:
                        tried_seats.clear()
                        task.message = f'重置尝试记录，继续抢票（第 {round_count} 轮）'

                    continue

                # 按优先级排序
                def get_priority(seat_id):
                    return task.seat_priorities.get(str(seat_id), 2)

                available_seats.sort(key=get_priority)

                # 取前 N 个座位进行并行抢票（N = min(并行数, 剩余需要数量, 可用座位数)）
                remaining = task.target_count - reserved_count
                batch_size = min(task.parallel_workers, remaining, len(available_seats))
                seats_to_try = available_seats[:batch_size]

                task.message = f'第 {round_count} 轮：并行尝试 {batch_size} 个座位... (已抢 {reserved_count}/{task.target_count})'

                # 使用线程池并行抢票
                with ThreadPoolExecutor(max_workers=batch_size) as executor:
                    futures = {
                        executor.submit(self._reserve_seat_worker, task, seat_id, date): seat_id
                        for seat_id in seats_to_try
                    }

                    for future in as_completed(futures):
                        if task.stop_flag:
                            break

                        seat_id = futures[future]
                        tried_seats.add(seat_id)

                        try:
                            success, sid, message = future.result(timeout=5)

                            if success:
                                with task.lock:
                                    if reserved_count < task.target_count:
                                        reserved_count += 1
                                        task.reserved_seats.append(sid)

                                        priority = get_priority(sid)
                                        priority_text = {1: '高', 2: '中', 3: '低'}.get(priority, '中')

                                        task.message = f'✅ 座位 {sid} 预订成功！(优先级:{priority_text}) 已抢 {reserved_count}/{task.target_count}'

                                        if reserved_count < task.target_count:
                                            api.send_notification(
                                                '✅ 座位预订成功',
                                                f'座位 {sid} 预订成功！已抢到 {reserved_count}/{task.target_count} 个座位'
                                            )
                            else:
                                task.message = f'❌ 座位 {sid} 失败: {message}'

                        except Exception as e:
                            task.message = f'❌ 座位 {seat_id} 异常: {str(e)}'

                # 检查是否已完成
                if reserved_count >= task.target_count:
                    break

                # 短暂休息后继续下一轮
                time.sleep(0.2)

            # 任务完成判断
            if reserved_count == task.target_count:
                task.status = 'success'
                task.message = f'🎉 抢票成功！已预定座位: {", ".join(map(str, task.reserved_seats))}'
                api.send_notification('🎉 抢票成功', task.message + '\n请尽快前往支付！')
            elif task.stop_flag:
                task.status = 'cancelled'
                task.message = '任务已取消'
            else:
                task.status = 'failed'
                task.message = f'❌ 抢票未完成，已尝试 {round_count} 轮'
                if task.reserved_seats:
                    task.message += f'\n✅ 已成功抢到部分座位: {", ".join(map(str, task.reserved_seats))}'
                api.send_notification('⚠️ 抢票未完成', task.message)

        finally:
            api.close()

    def _parallel_manual_reserve(self, task, date):
        """
        并行手动抢票模式
        同时尝试所有指定座位
        """
        api = BusAPI(task.config)
        success_seats = []
        failed_seats = []

        try:
            task.message = f'并行抢票：同时尝试 {len(task.seat_ids)} 个座位...'

            # 使用线程池并行抢所有指定座位
            with ThreadPoolExecutor(max_workers=min(len(task.seat_ids), 5)) as executor:
                futures = {
                    executor.submit(self._reserve_seat_worker, task, seat_id, date): seat_id
                    for seat_id in task.seat_ids
                }

                for future in as_completed(futures):
                    if task.stop_flag:
                        break

                    seat_id = futures[future]

                    try:
                        success, sid, message = future.result(timeout=5)

                        if success:
                            with task.lock:
                                success_seats.append(sid)
                                task.reserved_seats.append(sid)
                            task.message = f'✅ 座位 {sid} 预订成功！'
                        else:
                            failed_seats.append(sid)
                            task.message = f'❌ 座位 {sid} 失败: {message}'

                    except Exception as e:
                        failed_seats.append(seat_id)
                        task.message = f'❌ 座位 {seat_id} 异常: {str(e)}'

            # 任务完成判断
            if success_seats:
                task.status = 'success'
                task.message = f'🎉 抢票成功！已预定座位: {", ".join(map(str, success_seats))}'
                if failed_seats:
                    task.message += f'\n⚠️ 未能预订: {", ".join(map(str, failed_seats))}'
                api.send_notification('🎉 抢票成功', task.message + '\n请尽快前往支付！')
            else:
                task.status = 'failed'
                task.message = f'❌ 所选座位均未抢到: {", ".join(map(str, failed_seats))}'
                api.send_notification('❌ 抢票失败', task.message)

        finally:
            api.close()

    def get_all_tasks(self):
        """获取所有任务"""
        with self.lock:
            return [{
                'task_id': task.task_id,
                'bus_id': task.bus_id,
                'bus_info': {
                    'origin_address': task.bus_info.get('origin_address', ''),
                    'end_address': task.bus_info.get('end_address', ''),
                    'origin_time': task.bus_info.get('origin_time', '')
                },
                'status': task.status,
                'message': task.message,
                'created_at': task.created_at.strftime('%Y-%m-%d %H:%M:%S'),
                'start_time': task.start_time.strftime('%Y-%m-%d %H:%M:%S') if task.start_time else '',
                'reserved_seats': task.reserved_seats,
                'target_count': task.target_count,
                'auto_mode': task.auto_mode
            } for task in self.tasks.values()]

    def delete_task(self, task_id):
        """删除任务"""
        with self.lock:
            if task_id in self.tasks:
                task = self.tasks[task_id]
                task.stop_flag = True
                del self.tasks[task_id]

    def cancel_task(self, task_id):
        """取消任务"""
        with self.lock:
            if task_id in self.tasks:
                task = self.tasks[task_id]
                task.stop_flag = True
                task.status = 'cancelled'
                task.message = '任务已取消'
