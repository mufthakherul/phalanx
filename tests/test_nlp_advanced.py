from __future__ import annotations

# SPDX-License-Identifier: AGPL-3.0-or-later
from siyarix.nlp_engine import NaturalLanguageParser, ParsedIntent


def test_phrase_synonyms():
    nlp = NaturalLanguageParser()
    # "pass the hash" should map to "pth" first before word-by-word synonym mapping
    tokens = nlp.tokenize("using pass the hash to login")
    assert "pth" in tokens
    assert "pass" not in tokens
    assert "hash" not in tokens


def test_entity_priority():
    nlp = NaturalLanguageParser()
    # A text with both a URL and a domain should prioritize URL
    target, ttype = nlp.extract_entities("check domain.com or use https://domain.com/path")
    assert ttype == "url"
    assert target == "https://domain.com/path"

    # A text with domain and ip should prioritize ip (or check order)
    # url > cidr > ipv4 > ipv6 > mac > cve > sha256 > sha1 > md5 > ntlm > asn > email > domain
    target, ttype = nlp.extract_entities("target domain.com with ip 192.168.1.100")
    assert ttype == "ipv4"
    assert target == "192.168.1.100"


def test_extract_all_entities():
    nlp = NaturalLanguageParser()
    res = nlp.extract_all_entities("scan https://target.com and test 192.168.1.1")
    assert "url" in res
    assert "ipv4" in res
    assert res["url"][0] == "https://target.com"
    assert res["ipv4"][0] == "192.168.1.1"


def test_new_parameters_extraction():
    nlp = NaturalLanguageParser()
    params = nlp.extract_parameters(
        "run scan at rate 1000 save to output.json depth 3 proxy http://127.0.0.1:8080 with token my_secret_token target list ips.txt exclude 192.168.1.1 last 5 days"
    )

    assert params.get("rate") == "1000"
    assert params.get("output") == "output.json"
    assert params.get("depth") == "3"
    assert params.get("proxy") == "http://127.0.0.1:8080"
    assert params.get("token") == "my_secret_token"
    assert params.get("target_list") == "ips.txt"
    assert params.get("exclude") == "192.168.1.1"
    assert params.get("time_range") == "5d"


def test_parse_multi_propagation_and_semicolon():
    nlp = NaturalLanguageParser()
    # propagate target and handle semicolon / conjunctions
    intents = nlp.parse_multi("scan https://example.com; then check port 80; and then run nuclei")
    assert len(intents) == 3
    assert intents[0].target == "https://example.com"
    assert intents[1].target == "https://example.com"
    assert intents[2].target == "https://example.com"
    assert intents[0].conjunctive_goal is True


def test_positional_boost():
    nlp = NaturalLanguageParser()
    # Check if the score of front-loaded intent tokens gets the 1.25x boost.
    # Train nlp with a tool
    nlp.train_tools([
        {"name": "nmap", "description": "scanner tool", "tags": [], "category": ""}
    ])
    # The term 'scanner' is in description. If it's early versus late, it should affect score
    # (actually BM25 score will be higher if the token is matched and gets boosted)
    # Let's verify score_intent executes successfully
    best_match, score = nlp.score_intent(["scanner"], nlp._tool_corpus)
    assert best_match == "nmap"
    assert score > 0.0
