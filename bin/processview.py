"""
View module for the bash process manager script
"""
import os
import shutil

class PanelItem(object):
    pass

class PipelineRow(object):
    """
    Describes a single panel item
    """
    DEFAULT_HEIGHT = 4
    DEFAULT_MARGIN = 1
    def __init__(self, id, count, width, height=DEFAULT_HEIGHT, margin=DEFAULT_MARGIN, status=lambda i, t: 0):
        self._id = id
        self._count
        self._status = status
        self._width = width
        self._height = height
        self._margin = margin

    def create_windows(self, y, screen_w):
        """
        Make a row of n center-justified windows.
        """
        screen_mid = screen_w // 2
        total_width = self._count * self._width + (self._count - 1) * self._margin
        left = screen_mid - total_width // 2
        return [
            self._create_window(
                y, left + i * (self._width + self._margin),
                self._height, self._width, self._color, self.id
            )
            for i in range(self._count)
        ]

    @staticmethod
    def _create_window(y, x, height, width, color, id):
        ignore = []
        return PanelItem(y, x, height, width, color, decipher.get_next() id not in ignore else '')

