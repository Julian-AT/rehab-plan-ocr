#include "adapter.h"
#include "llama.h"
#include "mtmd.h"
#include "mtmd-helper.h"
#include <atomic>
#include <chrono>
#include <cstring>
#include <memory>
#include <string>
#include <vector>
using clock_type = std::chrono::steady_clock;
struct reha_vlm {
    llama_model * model = nullptr;
    llama_context * context = nullptr;
    mtmd_context * vision = nullptr;
    std::string family;
    clock_type::time_point deadline;
    std::atomic<bool> cancelled{false};
    ~reha_vlm() { if(vision) mtmd_free(vision); if(context) llama_free(context); if(model) llama_model_free(model); }
};
static bool stopped(void * ptr) {
    auto * s = static_cast<reha_vlm *>(ptr);
    return s->cancelled.load() || clock_type::now() >= s->deadline;
}
static bool loading(float, void * ptr) { return !stopped(ptr); }
extern "C" reha_vlm * reha_vlm_open(const char * model, const char * projector, const char * family, int budget_ms) {
    if (!model || !projector || !family || budget_ms < 1 || budget_ms > 60000) return nullptr;
    auto s = std::make_unique<reha_vlm>();
    s->family=family;
    if(s->family!="glm-ocr" && s->family!="paddleocr-vl-1.6") return nullptr;
    s->deadline=clock_type::now()+std::chrono::milliseconds(budget_ms);
    llama_backend_init();
    auto mp=llama_model_default_params();
    mp.n_gpu_layers=0; mp.progress_callback=loading; mp.progress_callback_user_data=s.get();
    s->model=llama_model_load_from_file(model,mp);
    if(!s->model || stopped(s.get())) return nullptr;
    char architecture[128] = {};
    llama_model_meta_val_str(s->model,"general.architecture",architecture,sizeof(architecture));
    if((s->family=="glm-ocr" && std::string(architecture)!="glm4") ||
       (s->family=="paddleocr-vl-1.6" && std::string(architecture)!="paddleocr")) return nullptr;
    auto cp=llama_context_default_params();
    cp.n_ctx=4096; cp.n_batch=512; cp.n_ubatch=512; cp.n_threads=2; cp.n_threads_batch=2;
    cp.abort_callback=stopped; cp.abort_callback_data=s.get();
    s->context=llama_init_from_model(s->model,cp);
    if(!s->context || stopped(s.get())) return nullptr;
    auto vp=mtmd_context_params_default(); vp.use_gpu=false;vp.n_threads=2;vp.warmup=false;
    vp.image_min_tokens=64;vp.image_max_tokens=1024;vp.progress_callback=loading;vp.progress_callback_user_data=s.get();
    s->vision=mtmd_init_from_file(projector,s->model,vp);
    if(!s->vision || !mtmd_support_vision(s->vision) || stopped(s.get())) return nullptr;
    return s.release();
}
extern "C" int reha_vlm_read(reha_vlm * s, const uint8_t * image, size_t size, int max_tokens, char * output, size_t capacity, int * tokens) {
    if(!s || !image || !output || !tokens || size>40*1024*1024 || max_tokens<1 || max_tokens>512 || capacity<1) return -1;
    *tokens=0;output[0]=0;
    if(stopped(s)) return 1;
    auto wrapper=mtmd_helper_bitmap_init_from_buf(s->vision,image,size,false,mtmd_helper_init_opt_default());
    if(!wrapper.bitmap || wrapper.video_ctx) return -1;
    std::unique_ptr<mtmd_bitmap,decltype(&mtmd_bitmap_free)> bitmap(wrapper.bitmap,mtmd_bitmap_free);
    const mtmd_bitmap * bitmaps[]={bitmap.get()};
    // Wrappers are supplied by libmtmd; these fixed OCR prompts match the pinned
    // checkpoints' user/assistant templates, without instructions from the photograph.
    const std::string marker=mtmd_get_marker(s->vision);
    const std::string prompt=s->family=="glm-ocr" ?
        "[gMASK]<sop><|user|>\n"+marker+"Text Recognition:<|assistant|>\n" :
        "<|begin_of_sentence|>User: "+marker+"OCR:\nAssistant:\n";
    std::unique_ptr<mtmd_input_chunks,decltype(&mtmd_input_chunks_free)> chunks(mtmd_input_chunks_init(),mtmd_input_chunks_free);
    mtmd_input_text text{prompt.c_str(),prompt.size(),false,true};
    if(mtmd_tokenize(s->vision,chunks.get(),&text,bitmaps,1) || mtmd_helper_get_n_tokens(chunks.get())+max_tokens>4096) return -1;
    if(stopped(s)) return 1;
    llama_memory_clear(llama_get_memory(s->context),true);
    llama_pos position=0;
    if(mtmd_helper_eval_chunks(s->vision,s->context,chunks.get(),0,0,512,true,&position)) return stopped(s)?1:-1;
    std::unique_ptr<llama_sampler,decltype(&llama_sampler_free)> sampler(llama_sampler_init_greedy(),llama_sampler_free);
    const auto * vocab=llama_model_get_vocab(s->model);
    size_t length=0;
    for(int i=0;i<max_tokens;++i) {
        if(stopped(s)) return 1;
        auto token=llama_sampler_sample(sampler.get(),s->context,-1);
        if(llama_vocab_is_eog(vocab,token)) return 0;
        int n=llama_token_to_piece(vocab,token,nullptr,0,0,false);
        std::vector<char> piece(static_cast<size_t>(n<0?-n:n)+1);
        n=llama_token_to_piece(vocab,token,piece.data(),static_cast<int>(piece.size()),0,false);
        if(n<0 || length+static_cast<size_t>(n)>=capacity) return 1;
        std::memcpy(output+length,piece.data(),n);length+=n;output[length]=0;++*tokens;
        auto batch=llama_batch_get_one(&token,1);
        if(llama_decode(s->context,batch)) return stopped(s)?1:-1;
    }
    return 1;
}
extern "C" void reha_vlm_cancel(reha_vlm * s) { if(s) s->cancelled.store(true); }
extern "C" void reha_vlm_close(reha_vlm * s) { delete s; }
