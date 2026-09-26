function createStorage(downloadRules) {
  const listeners = [];
  const values = downloadRules === undefined ? {} : { downloadRules };
  const writes = [];
  return {
    writes,
    onChanged: { addListener(listener) { listeners.push(listener); } },
    emit(changes, area = "local") {
      for (const listener of listeners) listener(changes, area);
    },
    local: {
      async get(key) { return Object.hasOwn(values, key) ? { [key]: structuredClone(values[key]) } : {}; },
      async set(update) {
        writes.push(structuredClone(update));
        const changes = {};
        for (const [key, newValue] of Object.entries(update)) {
          changes[key] = { oldValue: values[key], newValue: structuredClone(newValue) };
          values[key] = structuredClone(newValue);
        }
        for (const listener of listeners) listener(changes, "local");
      },
    },
  };
}

module.exports = { createStorage };
