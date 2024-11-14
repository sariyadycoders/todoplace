import { v4 as uuidv4 } from 'uuid';
import Upload from 'gcs-browser-upload';
import PQueue from 'p-queue';

const concurrency = 6;
const chunkSize = 262144 * 10;

class FileRetriver extends EventTarget {
  constructor(files, meta = {}) {
    super();
    this.files = files;
    this.meta = meta;
    this.dbName = 'files-db';
    this.collectionName = 'files';
    this.request = indexedDB.open(this.dbName);
    this.request.onupgradeneeded = (event) => {
      const db = event.target.result;
      if (!db.objectStoreNames.contains('files')) {
        db.createObjectStore('files', { keyPath: 'id', autoIncrement: true });
      }
    };
  }

  setFile = async (object) => {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(this.dbName);
      request.onsuccess = (event) => {
        const db = event.target.result;
        const transaction = db.transaction(['files'], 'readwrite');
        const objectStore = transaction.objectStore('files');
        const addRequest = objectStore.add(object);
        addRequest.onerror = (event) => reject(event.target.error);
        transaction.oncomplete = () =>
          resolve('Files with Blobs added successfully');
        transaction.onerror = (event) => reject(event.target.error);
      };
      request.onerror = (event) => reject(event.target.error);
    });
  };

  getFile = () => {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(this.dbName);

      request.onsuccess = (event) => {
        const db = event.target.result;
        const objectStore = db
          .transaction(['files'], 'readonly')
          .objectStore('files');
        const data = [];

        objectStore.openCursor().onsuccess = (event) => {
          const cursor = event.target.result;
          if (cursor) {
            data.push(cursor.value);
            cursor.continue();
          } else {
            resolve(data);
          }
        };
        objectStore.openCursor().onerror = (event) =>
          reject(event.target.error);
      };
      request.onerror = (event) => reject(event.target.error);
    });
  };

  deleteFile = (key) => {
    return new Promise((resolve, reject) => {
      const request = window.indexedDB.open(this.dbName);
      request.onsuccess = (event) => {
        const db = event.target.result;
        const transaction = db.transaction(['files'], 'readwrite');
        const objectStore = transaction.objectStore('files');
        const deleteRequest = objectStore.delete(key);
        deleteRequest.onsuccess = () => resolve('Data deleted successfully');
        deleteRequest.onerror = () =>
          reject(new Error('Error deleting data from IndexedDB'));
        transaction.oncomplete = () => resolve('File deleted successfully');
        transaction.onerror = (event) => reject(event.target.error);
      };
      request.onerror = () => reject(new Error('Error opening IndexedDB'));
    });
  };
}

// DO NOT change

let globalFiles = [];
let uploadObjects = {};
const fileRetriver = new FileRetriver();
export default {
  mounted() {
    const el = this.el;

    const { target, galleryId, change, albumId } = el.dataset;
    const form = el.querySelector(`#${target}`);

    ['change', 'drop'].forEach((evt) =>
      form.addEventListener(evt, (e) => {
        handleFileUpload(e);
      })
    );

    if (change == 'yes') {
      window.addEventListener('online', (event) => {
        resumeFilesMayBe(this, galleryId);
      });

      this.handleEvent('resume_pending_photos', async (e) => {
        let allStoreFiles = await fileRetriver.getFile();
        let inValidFilesDB = [];
        let inValidFiles = [];
        let allfilesData = [];
        let newFilesDB = [];

        inValidFilesDB = filterFiles(allStoreFiles, galleryId, false) || [];

        for (const file of inValidFilesDB) {
          if (e.photos[file.id] != null && e.photos[file.id] != 'undefined') {
            newFilesDB.push(file);
          }
        }

        for (const fileData of newFilesDB) {
          fileRetriver.deleteFile(fileData.id);
          let file = fileData.file;
          file.id = fileData.id;

          inValidFiles.push(file);
          allfilesData.push({
            id: fileData.id,
            size: file.size,
            type: file.type,
            name: file.name,
            error: fileData.error,
          });
        }

        await getUploadLinkAndCacheFile([], allfilesData, inValidFiles);
      });

      this.handleEvent('remove-uploading', async (e) => {
        var upload;
        for (const key in uploadObjects) {
          upload = uploadObjects[key];
          upload.pause();

          fileRetriver.deleteFile(key);
        }

        this.pushEvent('remove-uploading', { ids: Object.keys(uploadObjects) });
        uploadObjects = [];
      });

      this.handleEvent('delete_pending_photos', async (e) => {
        let allStoreFiles = await fileRetriver.getFile();
        let inValidFilesDB = filterFiles(allStoreFiles, galleryId, false);

        if (e.delete_all == true) {
          for (const fileData of inValidFilesDB) {
            fileRetriver.deleteFile(fileData.id);
          }
        } else {
          fileRetriver.deleteFile(e.photo.uuid);
        }
      });

      // this helps find the album_id we've stored in the local storage
      // helps initial upload for bulk folder upload and resumeability
      const parseAlbumIdFromStorage = (file_name, albums, album_id = null) => {
        console.log('albums check', albums);
        if (albums) {
          const { albums: album_list } = albums;

          const { id: found_album_id } = Object.keys(album_list)
            .map((key) => ({
              id: album_list[key].id,
              name: key,
            }))
            .filter((album) => file_name.includes(album.name))[0];
          return `${found_album_id}`;
        } else if (album_id) {
          return `${album_id}`;
        } else {
          return null;
        }
      };

      this.handleEvent('save_and_display', async (e) => {
        const files = globalFiles;
        const albums = JSON.parse(
          window.localStorage.getItem(`folder_albums_${galleryId}`)
        );
        globalFiles = [];

        for await (const file of files) {
          let url = e.urls[file.id];
          let invalid = e.invalid[file.id];
          let obj = {
            file: file,
            id: file.id,
            gallery_id: galleryId,
            album_id: parseAlbumIdFromStorage(file.name, albums, albumId),
          };

          if (url) {
            fileRetriver.setFile({
              ...obj,
              ...{ url: url, valid: true, error: null },
            });
          } else if (invalid) {
            fileRetriver.setFile({
              ...obj,
              ...{ valid: false, error: invalid.error },
            });
          } else {
            globalFiles.push(file);
          }
        }

        if (e.is_remove_message == true) {
          let storeFiles = await fileRetriver.getFile();
          let validFiles = filterFiles(storeFiles, galleryId);

          this.pushEvent('processing_message', { show: false });

          if (validFiles.length > 0) {
            upload(this, validFiles, galleryId);
          }
        }
      });

      resumeFilesMayBe(this, galleryId);
    }

    const handleFileUpload = async (event) => {
      let _files =
        event?.dataTransfer?.files ||
        event.target.files ||
        document.getElementById('photos').files;

      await startOrReumeUpload(_files);
    };

    const startOrReumeUpload = async (files) => {
      await getUploadLinkAndCacheFile(files);
    };

    const getUploadLinkAndCacheFile = async (
      files,
      fileData = [],
      newfiles = []
    ) => {
      if (newfiles.length == 0) {
        for await (const file of files) {
          const id = uuidv4();
          file.id = id;
          newfiles.push(file);
          fileData.push({
            id: id,
            size: file.size,
            type: file.type,
            name: file.name,
          });
        }
      }

      globalFiles = newfiles;
      await getSessionUrl(this, fileData);
    };

    const getSessionUrl = async (component, fileData) => {
      return new Promise((resolve, reject) => {
        component.pushEvent('processing_message', { show: true });

        component.pushEvent(
          'get_signed_url',
          {
            files: fileData,
            gallery_id: galleryId,
          },
          (reply) => {
            resolve(reply);
          }
        );
      });
    };

    this.handleEvent('folder_albums', (albums) => {
      window.localStorage.setItem(
        `folder_albums_${galleryId}`,
        JSON.stringify(albums)
      );
    });
  },
  updated() {},
};

function filterFiles(files, galleryId, check = true) {
  return files.filter(function (file) {
    return file.valid == check && file.gallery_id == galleryId;
  });
}

async function resumeFilesMayBe(component, galleryId) {
  console.log('reloading pending photos');
  let allStoreFiles = await fileRetriver.getFile();
  let storeFiles = [];
  let inValidFiles = [];

  storeFiles = filterFiles(allStoreFiles, galleryId) || [];
  inValidFiles = filterFiles(allStoreFiles, galleryId, false) || [];

  if (storeFiles.length >= 1) {
    const albums = JSON.parse(
      window.localStorage.getItem(`folder_albums_${galleryId}`)
    );

    for (let index = 0; index < storeFiles.length; index++) {
      let file = storeFiles[index];
      component.pushEvent('add_resumeable_photos', {
        id: file.id,
        name: file.file.name,
        gallery_id: galleryId,
        type: file.file.type,
        size: file.file.size,
      });
    }

    component.pushEvent('add_albums', {
      albums: albums?.albums || {},
    });

    upload(component, storeFiles, galleryId);
  }

  if (inValidFiles.length >= 1) {
    let filesData = [];
    for (const fileData of inValidFiles) {
      const file = fileData.file;

      filesData.push({
        id: fileData.id,
        size: file.size,
        type: file.type,
        name: file.name,
        error: fileData.error,
      });
    }

    component.pushEvent('pending_photos', {
      files: filesData,
      gallery_id: galleryId,
    });
  }
}

async function uploadFile(
  component,
  file,
  url,
  id,
  currentChunk,
  chunkLength,
  galleryId,
  albumId = null
) {
  const upload = new Upload({
    id,
    url,
    file,
    chunkSize,
    onChunkUpload: (info) => {
      const { uploadedBytes, totalBytes } = info;
      const progress = Math.round((uploadedBytes / totalBytes) * 100);
      const entry = document.querySelector(`#photos_new-${id} .progress`);

      if (entry) {
        entry.innerHTML = `${progress}%`;
        entry.value = progress;
      }

      component.pushEvent('progress_custom', {
        id,
        current_chunk: currentChunk,
        chunk_length: chunkLength,
        progress: progress || 0,
        name: file.name,
        size: file.size,
        type: file.type,
        gallery_id: galleryId,
      });

      console.log('Chunk uploaded', info);
    },
  });

  try {
    console.log('starting upload', id);
    await upload.start();

    component.pushEvent(
      'photo_done',
      {
        id,
        name: file.name,
        album_id: albumId,
      },
      (reply) => {
        delete uploadObjects[id];
        fileRetriver.deleteFile(id);
      }
    );
    console.log('ending upload', id);
  } catch (e) {
    console.log('Upload failed!', e);
  }
}

function nextChunk(
  component,
  currentChunk,
  chunkLength,
  files,
  queue,
  galleryId
) {
  console.log('starting chunk', currentChunk, 'of', chunkLength);

  for (const file of files) {
    queue.add(() =>
      uploadFile(
        component,
        file.file,
        file.url,
        file.id,
        currentChunk,
        chunkLength,
        galleryId,
        file.album_id
      )
    );
  }
}

function chunks(arr, chunkSize) {
  if (chunkSize <= 0) throw 'Invalid chunk size';
  var R = [];
  for (var i = 0, len = arr.length; i < len; i += chunkSize)
    R.push(arr.slice(i, i + chunkSize));
  return R;
}

function upload(component, storedFiles, galleryId) {
  const chunkFiles = [...chunks(storedFiles, 5000)];
  let currentChunk = 0;
  const chunkLength = chunkFiles.length;
  const queue = new PQueue({ concurrency });

  nextChunk(
    component,
    currentChunk,
    chunkLength,
    chunkFiles[currentChunk],
    queue,
    galleryId
  );

  queue.on('idle', () => {
    const newCurrentChunk = currentChunk + 1;
    if (newCurrentChunk < chunkLength) {
      nextChunk(
        newCurrentChunk,
        chunkLength,
        chunkFiles[newCurrentChunk],
        queue,
        galleryId
      );

      currentChunk = newCurrentChunk;
    } else {
      console.log('done');
      window.localStorage.removeItem(`folder_albums_${galleryId}`);
    }
  });
}
