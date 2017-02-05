import socket, datetime, time

now = datetime.datetime.now()
timestamp = int(time.time())

since_midnight = (
    now -
    now.replace(hour=0, minute=0, second=0)
).seconds

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.sendto('devday/clock/set:%d' % timestamp, ('127.0.0.1', 4444))
sock.sendto('devday/clock/midnight:%d' % since_midnight, ('127.0.0.1', 4444))
#sock.sendto('devday/config_update:updated', ('127.0.0.1', 4444))
