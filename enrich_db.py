import os
import json
import time
import glob
import google.generativeai as genai

# Setup API Key
api_key = os.environ.get("GEMINI_API_KEY")
if not api_key:
    print("ERROR: GEMINI_API_KEY environment variable is not set.")
    print("Usage: GEMINI_API_KEY='your_key' python3 enrich_db.py")
    exit(1)

genai.configure(api_key=api_key)

# Use Gemini 3.1 Flash Lite
model = genai.GenerativeModel('gemini-3.1-flash-lite')

PROMPT_TEMPLATE = """
You are an expert Italian linguist.
I will give you a list of Italian words and their primary English translations.

For EACH word, you must:
1. Identify its Part of Speech (e.g. noun, verb, adjective, adverb, preposition, conjunction).
2. Provide 1 to 3 highly common, everyday alternative English translations or synonyms. Do NOT provide obscure or rare translations.

Output ONLY valid JSON representing a dictionary where the keys are the exact 'id' of the word, and the values are objects containing the partOfSpeech and alternatives. Do not output any markdown tags.

Example Output format:
{{
  "1": {{ "partOfSpeech": "verb", "alternatives": ["synonym 1", "synonym 2"] }},
  "2": {{ "partOfSpeech": "noun", "alternatives": ["synonym 1"] }}
}}

Words to process:
{word_list_text}
"""

def process_batch(batch):
    if not batch: return {}
    
    # Construct the input text for this batch
    word_list_text = ""
    for w in batch:
        word_list_text += f"ID: {w['id']} | Italian: {w.get('italian', '')} | Primary English: {w.get('english', '')}\n"
        
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
                # Don't immediately fail the batch, try again since LLM JSON output might have been malformed
                time.sleep(base_delay)
                
    print(f"Failed to process batch of {len(batch)} words after {max_retries} retries.")
    return {}

def main():
    # Automatically find the Data directory whether we are inside or outside the Xcode folder
    data_dir = "Data"
    if not os.path.exists(data_dir):
        data_dir = "Le Parole/Data"
        
    json_files = glob.glob(os.path.join(data_dir, "words_*.json"))
    batch_size = 30 # Increased to 30 to ensure we finish within the 500 RPD limit
    
    for file_path in json_files:
        print(f"\nLoading {file_path}...")
        with open(file_path, "r", encoding="utf-8") as f:
            words = json.load(f)
            
        print(f"Loaded {len(words)} words.")
        
        # Collect words that need processing
        needs_processing = []
        for w in words:
            alts = w.get("alternatives", [])
            has_pos = "partOfSpeech" in w
            if len(alts) <= 1 or not has_pos:
                needs_processing.append(w)
                
        print(f"Found {len(needs_processing)} words needing enrichment in this file.")
        
        if not needs_processing:
            continue
            
        # Process in batches
        modified_count = 0
        
        # Create a dictionary for quick lookup to update the original list
        word_dict = {str(w.get("id", "")): w for w in words}
        
        for i in range(0, len(needs_processing), batch_size):
            batch = needs_processing[i:i+batch_size]
            print(f"Processing batch {i//batch_size + 1}/{(len(needs_processing) + batch_size - 1)//batch_size} ({len(batch)} words)...")
            
            enrichment_data = process_batch(batch)
            
            # Update the words using the returned dictionary mapping IDs to enrichment info
            for w in batch:
                w_id = str(w.get("id", ""))
                if w_id in enrichment_data:
                    data = enrichment_data[w_id]
                    alts = w.get("alternatives", [])
                    new_alts = set([a.lower() for a in alts])
                    for alt in data.get("alternatives", []):
                        new_alts.add(alt.lower())
                        
                    w["alternatives"] = list(new_alts)
                    w["partOfSpeech"] = data.get("partOfSpeech", "unknown")
                    
                    # Update it in the original list reference
                    if w_id in word_dict:
                        word_dict[w_id].update(w)
                    modified_count += 1
            
            # Save progress periodically (after every batch) to ensure we don't lose data
            with open(file_path, "w", encoding="utf-8") as f:
                json.dump(words, f, indent=4, ensure_ascii=False)
                
            # Strictly wait 5 seconds between batches to stay under the 15 RPM free tier limit
            print("  Waiting 5 seconds to respect API rate limits...")
            time.sleep(5)
            
        print(f"Completed! Saved {modified_count} modifications to {file_path}")

if __name__ == "__main__":
    main()
