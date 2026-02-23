import random
import instana
import os
import sys
import time
import logging
import uuid
import json
import requests
import traceback

from flask import Flask, Response, request, jsonify
from rabbitmq import Publisher

# Prometheus
import prometheus_client
from prometheus_client import Counter, Histogram

app = Flask(__name__)
app.logger.setLevel(logging.INFO)

CART = os.getenv('CART_HOST', 'cart')
USER = os.getenv('USER_HOST', 'user')
PAYMENT_GATEWAY = os.getenv('PAYMENT_GATEWAY', 'https://paypal.com/')

# Prometheus metrics
PromMetrics = {}
PromMetrics['SOLD_COUNTER'] = Counter('sold_count', 'Running count of items sold')
PromMetrics['AUS'] = Histogram('units_sold', 'Average Unit Sale', buckets=(1, 2, 5, 10, 100))
PromMetrics['AVS'] = Histogram(
    'cart_value',
    'Average Value Sale',
    buckets=(100, 200, 500, 1000, 2000, 5000, 10000)
)

# -------------------------
# Global error handler
# -------------------------
@app.errorhandler(Exception)
def exception_handler(err):
    app.logger.error(traceback.format_exc())
    return str(err), 500

# -------------------------
# Health check
# -------------------------
@app.route('/health', methods=['GET'])
def health():
    return 'OK'

# -------------------------
# Prometheus metrics
# -------------------------
@app.route('/metrics', methods=['GET'])
def metrics():
    res = []
    for m in PromMetrics.values():
        res.append(prometheus_client.generate_latest(m))
    return Response(res, mimetype='text/plain')

# -------------------------
# PAYMENT ENDPOINT (FIXED)
# -------------------------
@app.route('/pay/<id>', methods=['POST'])
def pay(id):
    app.logger.info(f'payment for {id}')

    # ---- FIX 1: Safe JSON parsing
    cart = request.get_json(silent=True)

    if not cart or 'items' not in cart:
        app.logger.error(f'invalid cart payload: {cart}')
        return 'invalid cart payload', 400

    app.logger.info(cart)

    anonymous_user = True

    # ---- Check user exists
    try:
        req = requests.get(f'http://{USER}:8080/check/{id}')
        if req.status_code == 200:
            anonymous_user = False
    except requests.exceptions.RequestException as err:
        app.logger.error(err)
        return str(err), 500

    # ---- Validate cart
    has_shipping = False
    for item in cart.get('items', []):
        if item.get('sku') == 'SHIP':
            has_shipping = True

    if cart.get('total', 0) == 0 or not has_shipping:
        app.logger.warning('cart not valid')
        return 'cart not valid', 400

    # ---- Dummy payment gateway call
    try:
        req = requests.get(PAYMENT_GATEWAY)
        app.logger.info(f'{PAYMENT_GATEWAY} returned {req.status_code}')
    except requests.exceptions.RequestException as err:
        app.logger.error(err)
        return str(err), 500

    if req.status_code != 200:
        return 'payment error', req.status_code

    # ---- Prometheus metrics
    item_count = countItems(cart.get('items', []))
    PromMetrics['SOLD_COUNTER'].inc(item_count)
    PromMetrics['AUS'].observe(item_count)
    PromMetrics['AVS'].observe(cart.get('total', 0))

    # ---- Generate order ID
    orderid = str(uuid.uuid4())

    queueOrder({
        'orderid': orderid,
        'user': id,
        'cart': cart
    })

    # ---- Add to order history (non-anonymous)
    if not anonymous_user:
        try:
            req = requests.post(
                f'http://{USER}:8080/order/{id}',
                data=json.dumps({'orderid': orderid, 'cart': cart}),
                headers={'Content-Type': 'application/json'}
            )
            app.logger.info(f'order history returned {req.status_code}')
        except requests.exceptions.RequestException as err:
            app.logger.error(err)
            return str(err), 500

    # ---- Delete cart
    try:
        req = requests.delete(f'http://{CART}:8080/cart/{id}')
        app.logger.info(f'cart delete returned {req.status_code}')
    except requests.exceptions.RequestException as err:
        app.logger.error(err)
        return str(err), 500

    if req.status_code != 200:
        return 'cart delete error', req.status_code

    return jsonify({'orderid': orderid})

# -------------------------
# Helpers
# -------------------------
def queueOrder(order):
    app.logger.info('queue order')

    delay = int(os.getenv('PAYMENT_DELAY_MS', 0))
    time.sleep(delay / 1000)

    headers = {}
    publisher.publish(order, headers)

def countItems(items):
    count = 0
    for item in items:
        if item.get('sku') != 'SHIP':
            count += item.get('qty', 0)
    return count

# -------------------------
# RabbitMQ
# -------------------------
publisher = Publisher(app.logger)

# -------------------------
# App entrypoint
# -------------------------
if __name__ == "__main__":
    app.logger.info(f'Payment gateway {PAYMENT_GATEWAY}')
    port = int(os.getenv("SHOP_PAYMENT_PORT", "8080"))
    app.logger.info(f'Starting on port {port}')
    app.run(host='0.0.0.0', port=port)
