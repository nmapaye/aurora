// Writes MMKV files with the MMKV Core that react-native-mmkv 3.3.0 vendors,
// calling the same entry points its JSI host object uses:
// MMKV::initializeMMKV(<Documents>/mmkv), MMKV::mmkvWithID("aurora"), and
// MMKV::set(std::string, key) for string values.
// Usage: gen <rootDir> <opsFile>; ops are lines "set<TAB>key<TAB>valueFile",
// "del<TAB>key", "trim", or "reopen" (close and reopen the instance, as a
// relaunch would). It prints each key MMKV reads back, with its
// string value in hex, so the manifest records MMKV's own reading.
#include "MMKV.h"
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>

static std::string slurp(const std::string &path) {
    std::ifstream in(path, std::ios::binary);
    std::stringstream ss; ss << in.rdbuf(); return ss.str();
}

int main(int argc, char **argv) {
    if (argc != 3) { std::cerr << "usage\n"; return 2; }
    MMKV::initializeMMKV(argv[1], MMKVLogNone);
    auto open = [] { return MMKV::mmkvWithID("aurora", MMKV_SINGLE_PROCESS, nullptr, nullptr); };
    MMKV *kv = open();
    if (!kv) { std::cerr << "open failed\n"; return 1; }
    std::ifstream ops(argv[2]);
    std::string line;
    while (std::getline(ops, line)) {
        std::istringstream f(line);
        std::string op, a, b;
        std::getline(f, op, '\t'); std::getline(f, a, '\t'); std::getline(f, b, '\t');
        if (op == "set") { if (!kv->set(slurp(b), a)) return 3; }
        else if (op == "del") kv->removeValueForKey(a);
        else if (op == "trim") kv->trim();
        else if (op == "reopen") { kv->sync(MMKV_SYNC); kv->close(); kv = open(); if (!kv) return 1; }
        else if (!op.empty()) { std::cerr << "bad op " << op << "\n"; return 2; }
    }
    // Read back through MMKV itself so each fixture records what MMKV returns.
    std::vector<std::string> keys = kv->allKeys();
    for (auto &k : keys) { std::string v; kv->getString(k, v); std::cout << k << "\t";
        for (unsigned char ch : v) { static const char *h = "0123456789abcdef"; std::cout << h[ch >> 4] << h[ch & 15]; }
        std::cout << "\n"; }
    kv->sync(MMKV_SYNC);
    kv->close();
    MMKV::onExit();
    return 0;
}
