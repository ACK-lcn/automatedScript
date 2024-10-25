import os
import datasets
from datasets.utils.file_utils import DownloadConfig

filePath = './datasets'
data_names = os.listdir(filePath)

#data_names = ["piqa"] ## "hellaswag"]
cache_dir = "/data-3/cache_all/huggingface_cache"

for data_name in range(len(data_names)):
#for data_name in data_names:
    #print(data_name)
    if data_names[data_name] == 'docred' or data_names[data_name] == 'electricity_load_diagrams' or data_names[data_name] == 'hybrid_qa' or data_names[data_name] == 's2orc':
        continue
    if data_name < 756: continue

    try:
        d = datasets.load_dataset(
            path=data_names[data_name],

            #path=data_name,
            cache_dir=cache_dir,
            download_config=DownloadConfig(
                cache_dir=cache_dir, use_etag=False),
        )
    except Exception as e:
        #print(e)
        print(f"{data_name} / {len(data_names)}")
        f = open('/data-3/cache_all/e.txt','a')
        f.write(str(e)+'\n')
        f.close()