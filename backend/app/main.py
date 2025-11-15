from fastapi import FastAPI

from .routes import session, accounts, proxy, orders
from .storage import STORE  # ensures store is initialized (DB or memory)


app = FastAPI(title="Extended Backend Adapter", version="0.1.0")


app.include_router(session.router, prefix="/session", tags=["session"])
app.include_router(accounts.router, prefix="/accounts", tags=["accounts"])
app.include_router(proxy.router, prefix="", tags=["proxy"])
app.include_router(orders.router, prefix="/orders", tags=["orders"])


