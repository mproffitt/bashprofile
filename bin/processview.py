#!/usr/bin/python3
"""
View module for the bash process manager script
"""
import os
import shutil
from time import sleep
import curses
import socket
import sys
from threading import Thread
import copy

class PanelConfig(object):
    STATUSES = [
        'READY',
        'RUNNING',
        'COMPLETE',
        'FAILED',
        'WAITING',
        'BLOCK'
    ]

    def __init__(self):
        pass

class PanelItem(object):
    x = 0
    y = 0
    width = 0
    height = 0
    colour = 0
    window = None

    def __init__(self, y, x, height, width):
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.window = curses.newwin(height, width, y, x)
        self.window.box()
        self.window.refresh()

    def update(self, colour, text):
        h, w = self.window.getmaxyx()
        self.window.bkgd(' ', curses.color_pair(colour))
        self.window.box()
        self.window.addstr(
            1,
            2,
            ' {0} '.format(text) if text else ' '
        )
        self.window.refresh()

class ProcessItem(object):
    index = 0
    process = ''
    _status = ''
    _returncode = -1
    panelitem = None

    def __init__(self, index, process, panelitem):
        self.index = index
        self.process = ''
        self.panelitem = panelitem

    @property
    def status(self):
        if self._status == 'COMPLETE' and self.returncode > 0:
            return 'FAILED'
        return self._status

    @status.setter
    def status(self, status):
        status = status.split('=')[0].upper()
        if status == 'COMPLETE' and self.returncode > 0:
            self._status = 'FAILED'
        self._status = status

    @property
    def returncode(self):
        return self._returncode if isinstance(self._returncode, int) else -1

    @returncode.setter
    def returncode(self, returncode):
        self._returncode = returncode

    @property
    def colour(self):
        return PanelConfig.STATUSES.index(self.status) + 1 if self.status != '' else 0

    def update(self, status, returncode):
        self.returncode = returncode
        self.status = status
        self.panelitem.update(self.colour, '{0}'.format(self._returncode))


class PipelineRow(object):
    """
    Describes a single panel item
    """
    DEFAULT_WIDTH = 8
    DEFAULT_HEIGHT = 4
    DEFAULT_MARGIN = 4
    def __init__(self, index, items, screen_w, width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, margin=DEFAULT_MARGIN):
        self._id = index
        self._count = len(items)
        self._queue = items
        self._width = width
        self._height = height
        self._margin = margin

        y = ((self._id + 1) * height) + (margin * self._id)
        self.columns = self.create_windows(y, screen_w)

    def create_windows(self, y, screen_w):
        """
        Make a row of n center-justified windows.
        """
        screen_mid = screen_w // 2
        total_width = ((self._count * self._width) + ((self._count - 1) * self._margin))
        left = screen_mid - total_width // 2
        return [
            ProcessItem(
                index,
                self._queue[index],
                PipelineRow._create_window(
                    y,
                    left + index * (self._width + self._margin),
                    self._height,
                    self._width
                )
            )
            for index, process in enumerate(self._queue)
        ]

    def update(self, columns):
        for index, column in enumerate(columns):
            status, returncode = column
            self.columns[index].update(status, returncode)

    @staticmethod
    def _create_window(y, x, height, width):
        return PanelItem(y, x, height, width)

class ProcessView(Thread):
    screen = None
    _grid = []
    MAXITEMS = 16

    def __init__(self, processes):
        Thread.__init__(self)
        # create an index on the process list
        self._processes = list(zip([i for i in range(len(processes))], processes))

    def run(self):
        self.screen = curses.initscr()
        if not self.screen:
            raise RuntimeError('No screen found')
        curses.noecho()
        curses.cbreak()
        self.screen.nodelay(True)
        self.screen.keypad(1)
        curses.start_color()
        curses.use_default_colors()
        curses.init_pair(1, curses.COLOR_WHITE, -1)
        curses.init_pair(2, curses.COLOR_BLACK, curses.COLOR_YELLOW)
        curses.init_pair(3, curses.COLOR_BLACK, curses.COLOR_GREEN)
        curses.init_pair(4, curses.COLOR_WHITE, curses.COLOR_RED)
        curses.init_pair(5, curses.COLOR_WHITE, curses.COLOR_BLUE)
        curses.init_pair(6, curses.COLOR_BLACK, curses.COLOR_WHITE)

        curses.init_pair(7, 254, -1)
        curses.curs_set(0)
        self._create_grid()

    def stop(self):
        curses.nocbreak()
        self.screen.keypad(0)
        curses.echo()
        curses.endwin()

    def _create_grid(self):
        grid = [
            self._processes[index:(index + ProcessView.MAXITEMS)]
            for index in range(0, len(self._processes), ProcessView.MAXITEMS)
        ]
        _, screen_w = self.screen.getmaxyx()
        self._grid = [PipelineRow(index, row, screen_w) for index, row in enumerate(grid)]

    def update(self, statuses):
        grid = [
            statuses[i:(i + ProcessView.MAXITEMS)]
            for i in range(0, len(statuses), ProcessView.MAXITEMS)
        ]
        for index, items in enumerate(grid):
            self._grid[index].update(items)
        #self.minilog(str(len(self._grid)))

class ServerThread(Thread):
    BLOCKSIZE = 2048
    running = True
    connection = None
    _data = None

    def __init__(self, connection, address):
        Thread.__init__(self)
        self.connection = connection
        self.name = address

    @property
    def data(self):
        return self._data

    def run(self):
        while self.running:
            try:
                data = self.connection.recv(self.BLOCKSIZE).decode('utf8').strip().replace('\n', '').replace('\r', '')
                if not data:
                    break
                try:
                    statuses = [item for item in data.split('|||')[0].split(';')[1:]]
                    returncodes = data.split('|||')[1].split(';')[1:]
                    data = list(zip(statuses, returncodes))
                    if len(data) > 0:
                        self._data = data
                    self.connection.sendall('OK'.encode('utf8'))
                except IndexError:
                    continue
            except (ConnectionResetError, BrokenPipeError) as exception:
                pass
        self.connection.close()

    def stop(self):
        self.running = False

class ViewServer(Thread):
    HOST = ''
    PORT = 8888
    socket = None
    running = True
    thread = None

    def __init__(self):
        Thread.__init__(self)
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            self.socket.bind((self.HOST, self.PORT))
        except socket.error as exception:
            raise
        self.socket.listen(10)
        connection, address = self.socket.accept()
        self.client = ServerThread(connection, address)

    @property
    def data(self):
        return self.client.data

    def run(self):
        self.client.start()
        while self.running:
            self.client.join()
            sleep(ViewRunner.SLEEP_INTERVAL)

    def stop(self):
        print('Done - shutting down thread')
        self.client.stop()
        self.running = False

class ViewRunner:
    SLEEP_INTERVAL = .05
    processes = None
    view = None
    server = None

    def __init__(self):
        Thread.__init__(self)
        self.processes = [process.split('~~~')[0] for process in os.environ['EXPORTED_QUEUE'].split('%%%')[1:]]
        self.view = ProcessView(self.processes)
        self.server = ViewServer()
        self.view.start()
        self.server.start()

    def run(self):
        """
        Create the principle view and update from the environment
        """
        try:
            while True:
                self.view.join()
                #self.server.join()
                if self.server.data is not None:
                    self.view.update(self.server.data)

                key = ''
                try:
                    key = self.view.screen.getkey()
                except:
                    pass
                sleep(ViewRunner.SLEEP_INTERVAL)
        except KeyboardInterrupt:
            pass

        self.view.stop()
        #print(self.server.data)
        print('Done - shutting down server')
        self.server.stop()

if __name__ == '__main__':
    process_view = ViewRunner()
    process_view.run()
    #runner = ViewServer()
    #runner.start()
