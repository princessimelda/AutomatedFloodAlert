"""Separate public inbox, recipient identity and privileged operator actions."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query

from .alert_auth import operator, recipient
from .alert_models import ActionInput, EventInput, PublishedAlert, RuleInput


def alert_router(settings, store):
    router = APIRouter(prefix="/api/v1", tags=["Student alert prototype"])
    manage = operator(settings, "operator", "approver")
    approve = operator(settings, "approver")
    ingest = operator(settings, "integration", "operator")
    rules_reader = operator(settings, "integration", "operator", "approver")

    @router.get("/alerts", response_model=list[PublishedAlert])
    def published(
        place_id: Annotated[str | None, Query(pattern="^[a-z0-9][a-z0-9-]{0,63}$")] = None,
    ):
        return store.public_alerts(place_id)

    @router.get("/alerts/{alert_id}", response_model=PublishedAlert)
    def public_detail(alert_id: UUID):
        for row in store.public_alerts():
            if row.id == alert_id:
                return row
        raise HTTPException(404)

    @router.post("/events", status_code=202)
    def receive(request: EventInput, actor=Depends(ingest)):
        return store.ingest(request, actor)

    @router.post("/alerts", status_code=202)
    def manual(request: EventInput, actor=Depends(operator(settings, "operator"))):
        if request.event_kind != "manual_report":
            raise HTTPException(422)
        return store.ingest(request, actor)

    @router.get("/events")
    def events(actor=Depends(rules_reader)):
        return store.events(actor)

    @router.post("/alert-rules", status_code=201)
    def rule(request: RuleInput, actor=Depends(approve)):
        return store.create_rule(request, actor)

    @router.get("/alert-rules")
    def rules(actor=Depends(rules_reader)):
        return store.rules()

    @router.get("/admin/alerts")
    def history(actor=Depends(manage)):
        return store.history()

    @router.get("/admin/alerts/{alert_id}")
    def detail(alert_id: UUID, actor=Depends(manage)):
        return store.detail(alert_id)

    @router.get("/admin/alerts/{alert_id}/audit")
    def audit(alert_id: UUID, actor=Depends(manage)):
        return store.audit_log(alert_id)

    for action in ["approve", "publish", "resolve", "cancel"]:

        def transition_endpoint(action_name):
            def apply(
                alert_id: UUID,
                request: ActionInput,
                actor=Depends(approve if action_name == "approve" else manage),
            ):
                return store.transition(alert_id, action_name, request, actor)

            return apply

        router.add_api_route(
            "/alerts/{alert_id}/" + action,
            transition_endpoint(action),
            methods=["POST"],
            name=action + "_alert",
        )

    @router.post("/alerts/{alert_id}/acknowledge")
    def acknowledge(alert_id: UUID, user_id=Depends(recipient(settings))):
        return store.acknowledge(alert_id, user_id)

    @router.get("/notifications")
    def notifications(actor=Depends(manage)):
        return store.notifications()

    @router.get("/reports/alerts")
    def report(actor=Depends(manage)):
        return store.report()

    return router
