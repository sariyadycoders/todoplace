import Sortable from 'sortablejs';

export default {
  mounted() {
    let sorter = new Sortable(this.el, {
      animation: 150,
      delay: 100,
      dragClass: 'drag-item',
      ghostClass: 'drag-ghost',
      forceFallback: true,
      onEnd: (e) => {
        if (e?.item && this?.el?.children) {
          let params = positionChange(
            e.item.dataset.photo_id,
            Array.from(this.el.children).map((el) =>
              parseInt(el.dataset.photo_id)
            )
          );

          this.pushEventTo(this.el, 'update_photo_position', params);
        }
      },
    });
  },
};

// Change position of photo
const positionChange = (movedId, order) => {
  const orderLen = order.length;

  if (orderLen < 2) {
    return false;
  }

  if (order[0] == movedId) {
    return {
      photo_id: movedId,
      type: 'before',
      args: [order[1]],
    };
  }
  if (order[orderLen - 1] == movedId) {
    return {
      photo_id: movedId,
      type: 'after',
      args: [order[orderLen - 2]],
    };
  }

  if (orderLen < 3) {
    return false;
  }

  for (let i = 1; i + 1 < orderLen; i += 1) {
    if (order[i] == movedId) {
      return {
        photo_id: movedId,
        type: 'between',
        args: [order[i - 1], order[i + 1]],
      };
    }
  }

  return false;
};
