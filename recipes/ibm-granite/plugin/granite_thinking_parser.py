from vllm.reasoning.abs_reasoning_parsers import ReasoningParserManager
from vllm.reasoning.deepseek_r1_reasoning_parser import DeepSeekR1ReasoningParser


@ReasoningParserManager.register_module("granite_thinking_parser")
class GraniteThinkingReasoningParser(DeepSeekR1ReasoningParser):

    def extract_reasoning(self, model_output, request):
        reasoning_content, final_content = super().extract_reasoning(
            model_output, request
        )

        if final_content is not None:
            final_content = final_content.lstrip("\n")

        if (
            hasattr(request, "chat_template_kwargs")
            and request.chat_template_kwargs
            and request.chat_template_kwargs.get("enable_thinking") is False
            and final_content is None
        ):
            reasoning_content, final_content = None, reasoning_content

        return reasoning_content, final_content
