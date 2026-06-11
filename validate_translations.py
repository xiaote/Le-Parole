import os
import json
import time
import glob
import google.generativeai as genai

# Setup API Key
api_key = os.environ.get("GEMINI_API_KEY")
if not api_key:
    print("ERROR: GEMINI_API_KEY environment variable is not set.")
    print("Usage: GEMINI_API_KEY='your_key' python3 validate_translations.py")
    exit(1)

genai.configure(api_key=api_key)

# Use Gemini 3.1 Flash Lite
model = genai.GenerativeModel('gemini-3.1-flash-lite')

PROMPT_TEMPLATE = """
You are an expert Italian and English linguist.
I will give you a list of Italian words, their primary English translation, and a list of 'alternative translations' that were generated previously.

For EACH word, you must:
1. Review the 'alternatives' array.
2. Filter out ANY alternative translation that is NOT a valid synonym or correct translation of the Italian word in common, everyday context.
3. If an alternative translation is a hallucination (like "apricot" for "arancione"), completely unrelated, or a totally obscure/archaic meaning, remove it.
4. Keep the ones that are good, valid, everyday synonyms or translations.

Output ONLY valid JSON representing a dictionary where the keys are the exact 'id' of the word, and the values are the filtered list of alternatives (array of strings). Do not output any markdown tags.

Example Output format:
{{
  "1": ["valid synonym 1"],
  "2": ["valid synonym 1", "valid synonym 2"],
  "3": []
}}

Words to process:
{word_list_text}
"""

def process_batch(batch):
    if not batch: return {}
    
    # Construct the input text for this batch
    word_list_text = ""
    for w in batch:
        alts_str = json.dumps(w.get('alternatives', []), ensure_ascii=False)
        word_list_text += f"ID: {w['id']} | Italian: {w.get('italian', '')} | Primary English: {w.get('english', '')} | Alternatives: {alts_str}\n"
        
    prompt = PROMPT_TEMPLATE.format(word_list_text=word_list_text)
    
    max_retries = 5
    base_delay = 5
    
    for attempt in range(max_retries):
        try:
            response = model.generate_content(prompt)
            text = response.text.strip()
            
            # Clean markdown if present
            if text.startswith("```json"):
                text = text[7:]
            elif text.startswith("```"):
                text = text[3:]
            if text.endswith("```"):
                text = text[:-3]
            text = text.strip()
            
            data = json.loads(text)
            return data
            
        except Exception as e:
            error_msg = str(e).lower()
            if "429" in error_msg or "quota" in error_msg or "exhausted" in error_msg:
                delay = base_delay * (2 ** attempt)
                print(f"Rate limited on batch. Retrying in {delay}s...")
                time.sleep(delay)
            else:
                print(f"Failed to process batch (Attempt {attempt+1}/{max_retries}): {e}")
                time.sleep(base_delay)
                
    print(f"Failed to process batch of {len(batch)} words after {max_retries} retries.")
    return {}

def main():
    data_dir = "Data"
    if not os.path.exists(data_dir):
        data_dir = "Le Parole/Data"
        
    json_files = glob.glob(os.path.join(data_dir, "words_*.json"))
    batch_size = 40 
    
    total_removed = 0
    total_checked = 0
    
    for file_path in json_files:
        print(f"\nLoading {file_path}...")
        with open(file_path, "r", encoding="utf-8") as f:
            words = json.load(f)
            
        # Collect words that actually have alternatives to check
        needs_processing = [w for w in words if w.get('alternatives')]
        if not needs_processing:
            continue
            
        print(f"Found {len(needs_processing)} words to validate in this file.")
        
        modified_count = 0
        for i in range(0, len(needs_processing), batch_size):
            batch = needs_processing[i:i+batch_size]
            print(f"Processing batch {i//batch_size + 1}/{(len(needs_processing) + batch_size - 1)//batch_size}...")
            
            updates = process_batch(batch)
            if not updates:
                continue
                
            for w in words:
                word_id = w['id']
                if word_id in updates:
                    old_alts = w.get('alternatives', [])
                    new_alts = updates[word_id]
                    
                    if isinstance(new_alts, list) and len(new_alts) < len(old_alts):
                        removed = set(old_alts) - set(new_alts)
                        total_removed += len(removed)
                        print(f"  Flagged for '{w.get('italian')}': removed {list(removed)}")
                        w['alternatives'] = new_alts
                        modified_count += 1
                        
            total_checked += len(batch)
            time.sleep(1) # Small delay to be safe
            
        if modified_count > 0:
            with open(file_path, "w", encoding="utf-8") as f:
                json.dump(words, f, indent=4, ensure_ascii=False)
            print(f"Saved {file_path}. Modified {modified_count} words.")
            
    print(f"\nValidation complete! Checked {total_checked} words and removed {total_removed} hallucinated translations.")

if __name__ == "__main__":
    main()
