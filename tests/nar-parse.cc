// Malformed-NAR rejection, ported from upstream libutil-tests/archive.cc
// (fixtures in tests/data/nars). The import path (addToStoreFromDump ->
// parseDump) must reject these byte streams with the exact class of
// error; a parser that lets one through writes attacker-controlled
// names (., .., x/y, NUL) into the store. duplicate.nar (unsorted
// directory entries) comes from upstream's functional nars.sh.
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <regex>
#include <sstream>
#include <string>

#include <nix/util/archive.hh>
#include <nix/util/fs-sink.hh>
#include <nix/util/serialise.hh>

using namespace nix;

static int testNum = 0, failures = 0;

static void ok(bool cond, const std::string & desc, const std::string & detail = "")
{
	testNum++;
	if (cond)
		printf("ok %d - %s\n", testNum, desc.c_str());
	else {
		printf("not ok %d - %s%s%s\n", testNum, desc.c_str(),
			detail.empty() ? "" : ": ", detail.c_str());
		failures++;
	}
}

// error messages quote names with ANSI color escapes; strip before match
static std::string stripAnsi(std::string s)
{
	static const std::regex ansi("\x1b\\[[0-9;]*m");
	return std::regex_replace(s, ansi, "");
}

int main(int argc, char ** argv)
{
	if (argc != 2) {
		fprintf(stderr, "usage: %s <ignored-store-root>\n", argv[0]);
		return 1;
	}

	auto dataDir = std::filesystem::path(__FILE__).parent_path() / "data/nars";

	struct Case
	{
		const char * name;
		const char * message; // expected substring of the error
	};
	static const Case cases[] = {
		{"invalid-tag-instead-of-contents", "bad archive: expected tag 'contents', got 'AAAAAAAA'"},
		{"nul-character", "bad archive: NAR contains invalid file name 'f"},
		{"dot", "bad archive: NAR contains invalid file name '.'"},
		{"dotdot", "bad archive: NAR contains invalid file name '..'"},
		{"slash", "bad archive: NAR contains invalid file name 'x/y'"},
		{"empty", "bad archive: NAR contains invalid file name ''"},
		{"executable-after-contents", "bad archive: expected tag ')', got 'executable'"},
		{"name-after-node", "bad archive: expected tag 'name'"},
		{"duplicate", "NAR directory is not sorted"},
	};

	for (auto & c : cases) {
		auto file = dataDir / (std::string(c.name) + ".nar");
		std::ifstream in(file, std::ios::binary);
		if (!in) {
			ok(false, fmt("%s: fixture readable", c.name), file.string());
			continue;
		}
		std::ostringstream ss;
		ss << in.rdbuf();
		std::string nar = ss.str();

		std::string got;
		try {
			StringSource source{nar};
			NullFileSystemObjectSink sink;
			parseDump(sink, source);
			got = "(no error)";
		} catch (Error & e) {
			got = stripAnsi(e.what());
		}
		ok(got.find(c.message) != std::string::npos,
			fmt("%s rejected", c.name),
			fmt("want substring \"%s\", got \"%s\"", c.message, got));
	}

	printf("1..%d\n", testNum);
	return failures ? 1 : 0;
}
