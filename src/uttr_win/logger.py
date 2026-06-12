import logging
from logging.handlers import RotatingFileHandler
from .settings import DATA_DIR

LOG_DIR = DATA_DIR / "logs"


def setup_logger(name: str = "uttr-win") -> logging.Logger:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger(name)
    if logger.handlers:
        return logger
    logger.setLevel(logging.DEBUG)

    file_handler = RotatingFileHandler(
        LOG_DIR / "uttr.log", maxBytes=512_000, backupCount=2, encoding="utf-8"
    )
    file_handler.setLevel(logging.DEBUG)

    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.INFO)

    fmt = logging.Formatter("[%(asctime)s] [%(levelname)s] [%(name)s] %(message)s")
    file_handler.setFormatter(fmt)
    console_handler.setFormatter(fmt)

    logger.addHandler(file_handler)
    logger.addHandler(console_handler)
    return logger
