import os

def replace_in_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    new_content = content.replace('include "kagent.', 'include "maduro.')
    new_content = new_content.replace('template "kagent.', 'template "maduro.')
    new_content = new_content.replace('define "kagent.', 'define "maduro.')
    new_content = new_content.replace('app.kubernetes.io/part-of: kagent', 'app.kubernetes.io/part-of: maduro')
    new_content = new_content.replace('name: kagent', 'name: maduro')
    
    # Be careful with just "kagent" as it might be part of other words, but in helm templates it's usually safe if scoped.
    # However, let's stick to the specific replacements first.
    
    if content != new_content:
        print(f"Updating {filepath}")
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)

def main():
    dirs = ['helm/maduro', 'helm/maduro-crds']
    for d in dirs:
        for root, _, files in os.walk(d):
            for file in files:
                if file.endswith('.yaml') or file.endswith('.tpl') or file.endswith('.txt'):
                    replace_in_file(os.path.join(root, file))

if __name__ == "__main__":
    main()
