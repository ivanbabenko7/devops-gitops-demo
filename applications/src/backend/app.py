import logging
import os
from datetime import datetime
from typing import Any

import mysql.connector
from flask import Flask, jsonify, request
from mysql.connector import Error

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)

logger = logging.getLogger(__name__)

app = Flask(__name__)

DB_CONFIG: dict[str, Any] = {
    "host": os.getenv("DB_HOST", "mysql"),
    "port": int(os.getenv("DB_PORT", "3306")),
    "database": os.getenv("DB_NAME", "appdb"),
    "user": os.getenv("DB_USER", "appuser"),
    "password": os.getenv("DB_PASSWORD", ""),
    "connection_timeout": 5,
    "autocommit": True,
}


def get_connection():
    return mysql.connector.connect(**DB_CONFIG)


def serialize_visit(row: dict[str, Any]) -> dict[str, Any]:
    created_at = row.get("created_at")

    if isinstance(created_at, datetime):
        row["created_at"] = created_at.isoformat(timespec="seconds")

    return row


def read_visit_data(connection) -> tuple[int, list[dict[str, Any]]]:
    cursor = connection.cursor(dictionary=True)

    try:
        cursor.execute("SELECT COUNT(*) AS count FROM visits")
        count_row = cursor.fetchone() or {"count": 0}
        count = int(count_row["count"])

        cursor.execute(
            """
            SELECT id, source, created_at
            FROM visits
            ORDER BY id DESC
            LIMIT 10
            """
        )

        recent = [
            serialize_visit(row)
            for row in cursor.fetchall()
        ]

        return count, recent
    finally:
        cursor.close()


def parse_source() -> str:
    payload = request.get_json(silent=True)

    if not isinstance(payload, dict):
        return "frontend"

    source = str(payload.get("source", "frontend")).strip()

    if not source:
        return "frontend"

    return source[:64]


@app.get("/healthz")
def healthz():
    return jsonify(
        status="ok",
        pod=os.getenv("POD_NAME", "local"),
    ), 200


@app.get("/readyz")
def readyz():
    try:
        connection = get_connection()

        try:
            cursor = connection.cursor()

            try:
                cursor.execute("SELECT 1 FROM visits LIMIT 1")
                cursor.fetchone()
            finally:
                cursor.close()
        finally:
            connection.close()

        return jsonify(status="ready"), 200

    except Error as exc:
        logger.warning("Readiness check failed: %s", exc)
        return jsonify(status="not-ready"), 503


@app.route("/api/visits", methods=["GET", "POST"])
def visits():
    try:
        connection = get_connection()

        try:
            if request.method == "POST":
                cursor = connection.cursor()

                try:
                    cursor.execute(
                        "INSERT INTO visits (source) VALUES (%s)",
                        (parse_source(),),
                    )
                finally:
                    cursor.close()

            count, recent = read_visit_data(connection)

        finally:
            connection.close()

        return jsonify(
            count=count,
            recent=recent,
            servedBy=os.getenv("POD_NAME", "local"),
        ), 200

    except Error:
        logger.exception("Database operation failed")
        return jsonify(error="database unavailable"), 503


@app.errorhandler(404)
def not_found(_error):
    return jsonify(error="not found"), 404
