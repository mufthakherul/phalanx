from __future__ import annotations

# SPDX-License-Identifier: AGPL-3.0-or-later
import pytest
from siyarix.planner import Planner, PlanStatus, PlanType


def test_new_templates_exist():
    planner = Planner()
    new_templates = [
        "windows_privesc",
        "linux_privesc_full",
        "lateral_movement",
        "persistence",
        "c2_setup",
        "phishing_campaign",
        "iot_firmware",
        "ics_recon",
        "mobile_android",
        "mobile_ios",
        "cloud_azure",
        "cloud_gcp",
        "k8s_attack",
        "crypto_attack",
        "ctf_forensics",
        "ctf_pwn",
        "ctf_crypto",
        "threat_hunting",
        "incident_response_full",
        "purple_team",
        "edr_bypass",
        "data_exfiltration",
        "social_engineering",
        "bug_bounty_web",
        "supply_chain",
    ]

    for tname in new_templates:
        plan = planner.create_from_template(tname, "10.0.0.1")
        assert len(plan.steps) > 0
        assert plan.steps[0].args.get("target") == "10.0.0.1"


def test_goal_routing_to_new_templates():
    planner = Planner()

    # Windows Privilege Escalation
    plan = planner.decompose_goal("find windows privilege escalation vectors on target.local")
    assert any(s.tool == "winpeas" for s in plan.steps) or any(s.tool == "powerup" for s in plan.steps)

    # Linux Privilege Escalation
    plan = planner.decompose_goal("check for linux privilege escalation capabilities on 10.0.0.5")
    assert any(s.tool == "linpeas" for s in plan.steps) or any(s.tool == "getcap" for s in plan.steps)

    # Lateral Movement
    plan = planner.decompose_goal("perform lateral movement using pass the hash against 10.0.0.2")
    assert any(s.tool == "crackmapexec" for s in plan.steps)

    # Phishing Campaign
    plan = planner.decompose_goal("set up a phishing campaign targeting company.com")
    assert any(s.tool == "gophish" for s in plan.steps) or any(s.tool == "theHarvester" for s in plan.steps)

    # IoT / SCADA
    plan = planner.decompose_goal("analyze firmware.bin for vulnerabilities")
    assert any(s.tool == "binwalk" for s in plan.steps)

    plan = planner.decompose_goal("enumerate modbus devices on 192.168.1.10")
    assert any(s.tool == "nmap" or s.tool == "mbtget" or s.tool == "plcscan" for s in plan.steps)


def test_direct_tool_keywords():
    planner = Planner()

    # WinPEAS
    plan = planner.decompose_goal("run winpeas on the system")
    assert plan.steps[0].tool == "winpeas"

    # Chisel
    plan = planner.decompose_goal("start chisel client tunnel")
    assert plan.steps[0].tool == "chisel"

    # Evilginx2
    plan = planner.decompose_goal("run evilginx2 reverse proxy")
    assert plan.steps[0].tool == "evilginx2"


def test_new_tool_alternatives():
    planner = Planner()

    # If winpeas is requested but only seatbelt is available
    plan = planner.decompose_goal("run winpeas on the target", available_tools=["seatbelt"])
    assert plan.steps[0].tool == "seatbelt"

    # If crackmapexec is requested but only netexec is available
    plan = planner.decompose_goal("run crackmapexec on target", available_tools=["netexec"])
    assert plan.steps[0].tool == "netexec"
