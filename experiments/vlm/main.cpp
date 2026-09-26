#include "adapter.h"
#include "nlohmann/json.hpp"
#include <chrono>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <sys/resource.h>
#include <vector>
int main(int argc,char ** argv) {
    if(argc!=6) { std::cerr<<"Usage: reha-vlm-read MODEL PROJECTOR FAMILY IMAGE OUTPUT_JSON\n";return 2; }
    const auto start=std::chrono::steady_clock::now();
    std::ifstream input(argv[4],std::ios::binary);
    std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)),std::istreambuf_iterator<char>());
    if(bytes.empty() || bytes.size()>40*1024*1024) return 2;
    std::unique_ptr<reha_vlm,decltype(&reha_vlm_close)> engine(reha_vlm_open(argv[1],argv[2],argv[3],60000),reha_vlm_close);
    std::vector<char> output(32768);int tokens=0;
    const int status=engine ? reha_vlm_read(engine.get(),bytes.data(),bytes.size(),256,output.data(),output.size(),&tokens) : -1;
    struct rusage usage{};getrusage(RUSAGE_SELF,&usage);
    nlohmann::json report={{"schema_version",1},{"status",status==0?"complete":status==1?"limited":"incompatible_or_failed"},{"text",output.data()},{"tokens",tokens},{"max_tokens",256},{"context",4096},{"image_max_tokens",1024},{"threads",2},{"cpu_only",true},{"approved",false},{"total_ms",std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-start).count()},{"peak_rss_bytes",usage.ru_maxrss}};
    std::ofstream(argv[5])<<report.dump(2, ' ', false, nlohmann::json::error_handler_t::replace)<<"\n";
    return status<0?1:0;
}
