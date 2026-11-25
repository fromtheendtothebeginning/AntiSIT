// 入场容器：只加 class，动画与延迟全部交给 CSS（.reveal[data-delay]）。
export default function Reveal({ as: Tag = "div", delay = 0, className = "", children, ...rest }) {
  return (
    <Tag className={"reveal " + className} data-delay={delay || undefined} {...rest}>
      {children}
    </Tag>
  );
}
