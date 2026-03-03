# coding=utf-8
"""
    @Author:零 若
    @file: proxy_capture.py
    @date: 2025/10/30 22:00
    @Python: 3.10.18
    别放弃,即使前方荆棘成林!
"""

import json
import logging
import socket
import threading
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
from urllib.parse import urlparse, parse_qs


class CapturedCredentials:
    """捕获的凭证数据"""

    def __init__(self):
        self.api_token = None
        self.api_time = None
        self.user_id = None
        self.capture_time = None
        self.is_complete = False
        self.lock = threading.Lock()

    def update(self, token=None, time_val=None, userid=None):
        """更新凭证"""
        with self.lock:
            if token:
                self.api_token = str(token).strip()
            if time_val:
                self.api_time = str(time_val).strip()
            if userid:
                self.user_id = str(userid).strip()

            # 检查是否所有凭证都已获取且有效
            if (self.api_token and len(self.api_token) > 0 and
                    self.api_time and len(self.api_time) > 0 and
                    self.user_id and len(self.user_id) > 0):
                self.is_complete = True
                self.capture_time = datetime.now()

    def to_dict(self):
        """转换为字典"""
        with self.lock:
            return {
                'API_TOKEN': self.api_token if self.api_token else None,
                'API_TIME': self.api_time if self.api_time else None,
                'USER_ID': self.user_id if self.user_id else None,
                'capture_time': self.capture_time.isoformat() if self.capture_time else None,
                'is_complete': self.is_complete
            }

    def reset(self):
        """重置凭证"""
        with self.lock:
            self.api_token = None
            self.api_time = None
            self.user_id = None
            self.capture_time = None
            self.is_complete = False


class ProxyRequestHandler(BaseHTTPRequestHandler):
    """代理请求处理器"""

    protocol_version = 'HTTP/1.1'

    # 目标域名
    TARGET_DOMAINS = [
        'hqapp1.bit.edu.cn'
    ]

    def __init__(self, *args, credentials=None, **kwargs):
        self.credentials = credentials
        self.logger = logging.getLogger(__name__)
        # 添加异常处理,避免连接错误导致程序崩溃
        try:
            super().__init__(*args, **kwargs)
        except (ConnectionResetError, BrokenPipeError, ConnectionAbortedError) as e:
            # 这些错误通常是客户端主动断开连接,可以安全忽略
            self.logger.debug(f"Connection closed by client: {e}")
        except Exception as e:
            self.logger.error(f"Unexpected error in handler: {e}")

    def log_message(self, format, *args):
        """重写日志方法,使用标准logging,且过滤掉噪音日志"""
        message = format % args

        # 过滤掉一些常见的噪音请求
        noise_keywords = [
            'favicon.ico',
            'apple-touch-icon',
            'ucweb.com',
            'taobao.com',
            'alipay.com'
        ]

        if any(keyword in message for keyword in noise_keywords):
            return

        self.logger.debug(f"{self.address_string()} - {message}")

    def handle(self):
        """重写handle方法,添加异常处理"""
        try:
            super().handle()
        except (ConnectionResetError, BrokenPipeError, ConnectionAbortedError):
            # 客户端断开连接,忽略
            pass
        except Exception as e:
            self.logger.debug(f"Error handling request: {e}")

    def do_GET(self):
        """处理GET请求"""
        self._handle_request()

    def do_POST(self):
        """处理POST请求"""
        self._handle_request()

    def do_CONNECT(self):
        """处理CONNECT请求(HTTPS)"""
        self.send_response(200, 'Connection Established')
        self.send_header('Connection', 'close')
        self.end_headers()

        # 对于HTTPS,我们只能记录域名,无法解密内容
        self.logger.info(f"HTTPS CONNECT to: {self.path}")

    def _should_ignore_request(self, url: str) -> bool:
        """
        判断是否应该忽略此请求
        
        Args:
            url: 请求URL
            
        Returns:
            是否忽略
        """
        # 检查是否包含目标域名
        is_target = any(domain in url for domain in self.TARGET_DOMAINS)
        return False if is_target else True

    def _handle_request(self):
        """处理HTTP请求"""
        try:
            # 解析URL
            parsed_url = urlparse(self.path)
            host = self.headers.get('Host', '')
            full_url = f"{host}{self.path}"

            # 检查是否应该忽略
            if self._should_ignore_request(full_url):
                # 直接返回200,不转发请求
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                self.send_header('Content-Length', '0')
                self.send_header('Connection', 'close')
                self.end_headers()
                return

            # 检查是否是目标API
            if 'hqapp1.bit.edu.cn' in parsed_url.netloc or 'hqapp1.bit.edu.cn' in self.path:
                self._capture_credentials()

            # 转发请求
            self._forward_request()

        except (ConnectionResetError, BrokenPipeError, ConnectionAbortedError):
            # 客户端断开,忽略
            pass
        except Exception as e:
            # 只记录非域名解析错误
            if 'getaddrinfo failed' not in str(e) and 'NameResolutionError' not in str(e):
                self.logger.error(f"Error handling request: {e}")

            try:
                self.send_error(500, f"Proxy Error: {str(e)}")
            except:
                pass

    def _capture_credentials(self):
        """捕获凭证信息"""
        try:
            # 从请求头中提取
            api_token = self.headers.get('apitoken')
            api_time = self.headers.get('apitime')

            # 从URL参数中提取userid
            parsed_url = urlparse(self.path)
            query_params = parse_qs(parsed_url.query)
            user_id = query_params.get('userid', [None])[0]

            if api_token or api_time or user_id:
                self.credentials.update(
                    token=api_token,
                    time_val=api_time,
                    userid=user_id
                )

                self.logger.info(
                    f"✅ 捕获到凭证 - "
                    f"Token: {'✓' if api_token else '✗'}, "
                    f"Time: {'✓' if api_time else '✗'}, "
                    f"UserID: {'✓' if user_id else '✗'}"
                )

                if self.credentials.is_complete:
                    self.logger.info("🎉 所有凭证已完整捕获!")

        except Exception as e:
            self.logger.error(f"Error capturing credentials: {e}")

    def _forward_request(self):
        """转发请求到目标服务器"""
        import requests

        try:
            # 解析目标URL
            if self.path.startswith('http'):
                url = self.path
            else:
                host = self.headers.get('Host', 'hqapp1.bit.edu.cn')
                url = f"http://{host}{self.path}"

            # 再次检查是否应该忽略
            if self._should_ignore_request(url):
                self.send_response(200)
                self.send_header('Content-Length', '0')
                self.send_header('Connection', 'close')
                self.end_headers()
                return

            # 准备请求头(移除代理相关的头)
            headers = dict(self.headers)
            headers.pop('Proxy-Connection', None)
            headers.pop('Proxy-Authenticate', None)
            headers.pop('Proxy-Authorization', None)

            # 读取请求体(如果有)
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length) if content_length > 0 else None

            # 发送请求
            response = requests.request(
                method=self.command,
                url=url,
                headers=headers,
                data=body,
                allow_redirects=False,
                timeout=10,  # 减少超时时间
                verify=False
            )

            # 返回响应
            self.send_response(response.status_code)

            # 转发响应头
            for key, value in response.headers.items():
                if key.lower() not in ['transfer-encoding', 'connection', 'keep-alive']:
                    self.send_header(key, value)

            self.send_header('Connection', 'close')
            self.end_headers()

            # 转发响应体
            if response.content:
                self.wfile.write(response.content)

        except (ConnectionResetError, BrokenPipeError, ConnectionAbortedError):
            pass
        except requests.exceptions.Timeout:
            # 超时不记录error,只记录warning
            self.logger.debug(f"Request timeout: {url[:100]}")
            try:
                self.send_error(504, "Gateway Timeout")
            except:
                pass
        except requests.exceptions.RequestException as e:
            # DNS解析失败等网络错误,不记录详细日志
            error_msg = str(e)
            if 'getaddrinfo failed' in error_msg or 'NameResolutionError' in error_msg:
                self.logger.debug(f"DNS resolution failed (ignored): {url[:50]}")
            else:
                self.logger.warning(f"Request failed: {error_msg[:100]}")

            try:
                self.send_error(502, "Bad Gateway")
            except:
                pass
        except Exception as e:
            error_msg = str(e)
            if 'Remote end closed' not in error_msg:
                self.logger.debug(f"Request error: {error_msg[:100]}")
            try:
                self.send_error(500, "Internal Error")
            except:
                pass


class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    """多线程HTTP服务器"""
    daemon_threads = True
    allow_reuse_address = True

    def handle_error(self, request, client_address):
        """重写错误处理,避免打印堆栈"""
        # 获取异常信息
        import sys
        exc_type, exc_value, exc_traceback = sys.exc_info()

        # 如果是连接错误,只记录debug级别日志
        if isinstance(exc_value, (ConnectionResetError, BrokenPipeError, ConnectionAbortedError)):
            logger = logging.getLogger(__name__)
            logger.debug(f"Connection error from {client_address}: {exc_value}")
        else:
            # 其他错误使用默认处理
            super().handle_error(request, client_address)


class ProxyCaptureServer:
    """代理捕获服务器"""

    def __init__(self, host='0.0.0.0', port=8888):
        """
        初始化代理服务器
        
        Args:
            host: 监听地址
            port: 监听端口
        """
        self.host = host
        self.port = port
        self.server = None
        self.server_thread = None
        self.credentials = CapturedCredentials()
        self.logger = logging.getLogger(__name__)
        self.is_running = False

    def get_local_ip(self):
        """获取本机IP地址"""
        try:
            # 创建一个UDP socket
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except Exception:
            return '127.0.0.1'

    def start(self):
        """启动代理服务器"""
        if self.is_running:
            self.logger.warning("Server is already running")
            return

        try:
            # 禁用SSL警告
            import urllib3
            urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

            # 创建请求处理器工厂函数
            def handler(*args, **kwargs):
                return ProxyRequestHandler(*args, credentials=self.credentials, **kwargs)

            # 创建服务器
            self.server = ThreadedHTTPServer((self.host, self.port), handler)

            # 在新线程中运行服务器
            self.server_thread = threading.Thread(target=self._run_server)
            self.server_thread.daemon = True
            self.server_thread.start()

            self.is_running = True

            local_ip = self.get_local_ip()

            self.logger.info(f"✅ 代理服务器已启动")
            self.logger.info(f"📡 监听地址: {self.host}:{self.port}")
            self.logger.info(f"🌐 本机IP: {local_ip}")
            self.logger.info(f"\n{'=' * 60}")
            self.logger.info(f"📱 手机配置步骤:")
            self.logger.info(f"1. 确保手机和电脑在同一WiFi网络")
            self.logger.info(f"2. 打开手机WiFi设置 → 选择已连接的WiFi → 配置代理")
            self.logger.info(f"3. 选择'手动'代理,填写:")
            self.logger.info(f"   服务器: {local_ip}")
            self.logger.info(f"   端口: {self.port}")
            self.logger.info(f"4. 保存后,打开北理工后勤系统访问班车页面")
            self.logger.info(f"5. 系统将自动捕获凭证")
            self.logger.info(f"{'=' * 60}\n")

        except Exception as e:
            self.logger.error(f"❌ 启动服务器失败: {e}")
            raise

    def _run_server(self):
        """运行服务器(在单独线程中)"""
        try:
            self.server.serve_forever()
        except Exception as e:
            self.logger.error(f"Server error: {e}")
            self.is_running = False

    def stop(self):
        """停止代理服务器"""
        if not self.is_running:
            return

        try:
            if self.server:
                self.server.shutdown()
                self.server.server_close()

            self.is_running = False
            self.logger.info("🛑 代理服务器已停止")

        except Exception as e:
            self.logger.error(f"停止服务器时出错: {e}")

    def get_credentials(self):
        """获取捕获的凭证"""
        return self.credentials.to_dict()

    def is_credentials_complete(self):
        """检查凭证是否完整"""
        return self.credentials.is_complete

    def reset_credentials(self):
        """重置凭证"""
        self.credentials.reset()
        self.logger.info("🔄 凭证已重置")

    def wait_for_credentials(self, timeout=300):
        """
        等待凭证捕获完成
        
        Args:
            timeout: 超时时间(秒)
            
        Returns:
            是否成功捕获
        """
        import time
        start_time = time.time()

        self.logger.info(f"⏳ 等待凭证捕获... (超时: {timeout}秒)")

        while time.time() - start_time < timeout:
            if self.credentials.is_complete:
                self.logger.info("✅ 凭证捕获完成!")
                return True
            time.sleep(1)

        self.logger.warning("⚠️ 凭证捕获超时")
        return False

    def __enter__(self):
        """上下文管理器入口"""
        self.start()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """上下文管理器退出"""
        self.stop()


# ==================== 测试代码 ====================

def main():
    """测试代理捕获服务器"""
    # 配置日志
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

    logger = logging.getLogger(__name__)

    try:
        # 创建代理服务器
        with ProxyCaptureServer(host='0.0.0.0', port=8888) as proxy:
            logger.info("代理服务器运行中,按 Ctrl+C 停止...")

            # 等待凭证捕获(5分钟超时)
            if proxy.wait_for_credentials(timeout=300):
                credentials = proxy.get_credentials()
                logger.info("\n捕获的凭证:")
                logger.info(json.dumps(credentials, indent=2, ensure_ascii=False))
            else:
                logger.warning("未能捕获完整凭证")
                credentials = proxy.get_credentials()
                logger.info(f"部分凭证: {credentials}")

    except KeyboardInterrupt:
        logger.info("\n\n用户中断")
    except Exception as e:
        logger.error(f"错误: {e}", exc_info=True)


if __name__ == "__main__":
    main()
