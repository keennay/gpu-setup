from vllm.reasoning.abs_reasoning_parsers import ReasoningParserManager
from vllm.reasoning.deepseek_r1_reasoning_parser import DeepSeekR1ReasoningParser


@ReasoningParserManager.register_module("super_v3")
class SuperV3ReasoningParser(DeepSeekR1ReasoningParser):
    def extract_reasoning(self, model_output, request):
        reasoning_content, final_content = super().extract_reasoning(
            model_output, request
        )
        if (
            hasattr(request, "chat_template_kwargs")
            and request.chat_template_kwargs
            and (
                request.chat_template_kwargs.get("enable_thinking") is False
                or request.chat_template_kwargs.get("force_nonempty_content") is True
            )
            and (final_content is None or not final_content.strip())
        ):
            """
            The original `deepseek_r1` reasoning parser this inherits from will automatically put everything in the reasoning content when it cannot parse out reasoning. This was fine for the DeepSeek R1 model that was not intended to be used without reasoning.
            1. Since the Nemotron 3 Nano and Super both have thinking off modes modulated by "enable_thinking=false" in the chat template kwargs, this change instead which will properly place the content in cases where there is no thinking enabled via config.
            2. There are rare cases where the model will output only reasoning without an end-think token `</think>` (e.g. reasoning exceeds max length), which results in empty content returned. End users may want to unilaterally avoid such cases and always have a content response even if the model does not finish its reasoning.
            """
            # Put all nonempty content into the content, rather than return content
            reasoning_content, final_content = None, reasoning_content

        return reasoning_content, final_content